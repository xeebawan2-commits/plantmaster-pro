import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new Error("GEMINI_API_KEY secret is missing");
    const input = await request.json();
    const mode = input.mode || "quick";
    const sourceRule = mode === "manual"
      ? "Use only supplied manuals, plant history, approved experiences and offlineReference. Do not use general or online facts not present in those sources."
      : mode === "deep"
      ? "Use supplied plant sources first, then use Google Search grounding for reputable technical information. Clearly identify manufacturer/manual, plant-history and online sources."
      : "Give a short, fast answer using the supplied plant context, manuals, experiences and safe engineering knowledge.";

    const prompt = `You are PlantMaster Gemini, an industrial maintenance decision-support assistant.
${sourceRule}
Never advise bypassing guards, interlocks, emergency stops, LOTO, pressure isolation or qualified-person requirements.
Rank likely causes, give safe checks in order, measurements, tools, possible parts, shutdown advice and escalation.
Return ONLY JSON with keys: answer (string), safety (string), confidence (string), sources (array of strings).

INPUT:\n${JSON.stringify(input).slice(0, 180000)}`;

    const body: Record<string, unknown> = {
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: mode === "deep" ? 0.25 : 0.15,
        responseMimeType: "application/json",
      },
    };
    if (mode === "deep") body.tools = [{ google_search: {} }];

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(key)}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) },
    );
    const raw = await response.text();
    if (!response.ok) throw new Error(raw);
    const result = JSON.parse(raw);
    const text = result.candidates?.[0]?.content?.parts?.map((part: { text?: string }) => part.text || "").join("") || "{}";
    let parsed: Record<string, unknown>;
    try { parsed = JSON.parse(text); } catch { parsed = { answer: text, safety: "Follow plant safety procedures and qualified-person requirements.", confidence: "Unverified", sources: [] }; }
    return new Response(JSON.stringify(parsed), { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error?.message || error) }), { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
