export function createAnalytics({ sb, $, esc, state, toast }) {
  let chartInstances = [];

  function destroyCharts() {
    chartInstances.forEach(c => c.destroy());
    chartInstances = [];
  }

  async function render() {
    $('#toolbar').hidden = false;
    $('#add').hidden = true;
    $('#search').placeholder = 'Search analytics...';
    $('#content').innerHTML = `<div class="card"><h3>Loading Analytics...</h3></div>`;
    
    try {
      const s = state();
      
      // Fetch relevant data
      const [woRes, assetsRes] = await Promise.all([
        sb.from('work_orders').select('status, created_at, completed_at, downtime_minutes').eq('plant_id', s.plant.id),
        sb.from('assets').select('id, name, running_state').eq('plant_id', s.plant.id).is('removed_at', null)
      ]);
      
      const workOrders = woRes.data || [];
      const assets = assetsRes.data || [];
      
      // Analytics Calculations
      const completed = workOrders.filter(w => w.status === 'completed');
      const open = workOrders.filter(w => w.status !== 'completed' && w.status !== 'cancelled');
      
      const totalDowntime = completed.reduce((sum, w) => sum + (w.downtime_minutes || 0), 0);
      const mttr = completed.length ? Math.round(totalDowntime / completed.length) : 0;
      
      // Calculate MTBF (very roughly for demo: Total uptime of all assets / number of breakdowns)
      // Assuming assets run 24/7 for the last 30 days
      const daysInMonth = 30;
      const totalAssumedUptimeMins = assets.length * daysInMonth * 24 * 60;
      const mtbf = completed.length ? Math.round((totalAssumedUptimeMins - totalDowntime) / completed.length / 60) : 0;

      $('#content').innerHTML = `
        <section class="module-head">
          <div>
            <h1>Analytics & KPIs</h1>
            <p>Plant performance, reliability metrics, and downtime</p>
          </div>
        </section>
        
        <div class="kpis" style="grid-template-columns: repeat(3, 1fr); margin-bottom: 20px;">
          <div class="kpi">
            <span>MTTR (Mean Time To Repair)</span>
            <strong>${mttr} <small>mins</small></strong>
            <small>Average repair time per work order</small>
          </div>
          <div class="kpi">
            <span>MTBF (Mean Time Between Failures)</span>
            <strong>${mtbf} <small>hrs</small></strong>
            <small>Average uptime between breakdowns</small>
          </div>
          <div class="kpi">
            <span>Total Downtime (Lifetime)</span>
            <strong>${Math.round(totalDowntime / 60)} <small>hrs</small></strong>
            <small>Across all completed work orders</small>
          </div>
        </div>

        <div class="grid dashboard-grid">
          <div class="card" style="padding: 20px; grid-column: span 1;">
            <h3>Work Order Status</h3>
            <canvas id="woChart" width="100" height="100"></canvas>
          </div>
          <div class="card" style="padding: 20px; grid-column: span 1;">
            <h3>Asset States</h3>
            <canvas id="assetChart" width="100" height="100"></canvas>
          </div>
        </div>
      `;

      // Render Charts
      destroyCharts();
      if (!window.Chart) return toast('Chart.js not loaded yet');

      const ctxWo = document.getElementById('woChart').getContext('2d');
      chartInstances.push(new Chart(ctxWo, {
        type: 'doughnut',
        data: {
          labels: ['Completed', 'Open/Pending'],
          datasets: [{
            data: [completed.length, open.length],
            backgroundColor: ['#34d399', '#fbbf24'],
            borderWidth: 0
          }]
        },
        options: {
          responsive: true,
          plugins: { legend: { labels: { color: '#f3f4f6' } } }
        }
      }));

      const running = assets.filter(a => a.running_state === 'running').length;
      const shutdown = assets.length - running;
      
      const ctxAsset = document.getElementById('assetChart').getContext('2d');
      chartInstances.push(new Chart(ctxAsset, {
        type: 'pie',
        data: {
          labels: ['Running', 'Shutdown'],
          datasets: [{
            data: [running, shutdown],
            backgroundColor: ['#0ea5e9', '#ef4444'],
            borderWidth: 0
          }]
        },
        options: {
          responsive: true,
          plugins: { legend: { labels: { color: '#f3f4f6' } } }
        }
      }));

    } catch (e) {
      $('#content').innerHTML = `<div class="error-state"><h2>Error</h2><p>${esc(e.message)}</p></div>`;
    }
  }

  return { render, stop: destroyCharts };
}
