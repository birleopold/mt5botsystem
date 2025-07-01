// Simple chart rendering using Chart.js (if loaded)
function renderLineChart(ctx, data, labels, label) {
  if (typeof Chart === 'undefined') return;
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: labels,
      datasets: [{
        label: label,
        data: data,
        fill: false,
        borderColor: '#4caf50',
        tension: 0.1
      }]
    },
    options: {
      responsive: true,
      plugins: { legend: { display: false } }
    }
  });
}
