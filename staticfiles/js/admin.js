document.addEventListener('DOMContentLoaded', function() {
  // Enhance tables
  document.querySelectorAll('.data-table').forEach(table => {
    table.querySelectorAll('th').forEach(th => {
      th.style.cursor = 'pointer';
      th.addEventListener('click', () => sortTable(th));
    });
  });

  // Add search functionality
  const search = document.createElement('input');
  search.placeholder = 'Search...';
  search.style.margin = '1rem 0';
  document.querySelector('.data-grid').prepend(search);
  
  search.addEventListener('input', (e) => {
    const term = e.target.value.toLowerCase();
    document.querySelectorAll('.data-table tbody tr').forEach(row => {
      row.style.display = row.textContent.toLowerCase().includes(term) ? '' : 'none';
    });
  });
});

function sortTable(th) {
  const table = th.closest('table');
  const colIndex = Array.from(th.parentNode.children).indexOf(th);
  const rows = Array.from(table.querySelectorAll('tbody tr'));
  
  rows.sort((a, b) => {
    const aVal = a.children[colIndex].textContent.trim();
    const bVal = b.children[colIndex].textContent.trim();
    return aVal.localeCompare(bVal, undefined, {numeric: true});
  });

  table.tBodies[0].append(...rows);
}
