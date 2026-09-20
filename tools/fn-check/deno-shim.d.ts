// Ambient declarations so `tsc` can type-check the edge functions without a
// Deno install. These mirror only the surface the functions actually use.
declare namespace Deno {
  function serve(handler: (req: Request) => Response | Promise<Response>): unknown;
  const env: { get(key: string): string | undefined };
}

declare module 'jsr:@supabase/supabase-js@2' {
  export interface PostgrestResult<T = any> { data: T; error: any; count?: number | null }
  export type SupabaseClient = any;
  export function createClient(url: string, key: string, options?: any): any;
}
