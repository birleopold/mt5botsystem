// Modern Django Admin Interactivity for Grappelli
// Row highlight on click
// Click-to-copy for IDs
// Quick filter/search for table rows

document.addEventListener('DOMContentLoaded', function() {
    // Row highlight on click
    document.querySelectorAll('tr').forEach(function(row) {
        row.addEventListener('click', function() {
            row.classList.toggle('selected');
        });
    });
    // Click-to-copy for ID fields
    document.querySelectorAll('.field-id').forEach(function(cell) {
        cell.style.cursor = 'pointer';
        cell.title = 'Click to copy';
        cell.addEventListener('click', function(e) {
            e.stopPropagation();
            navigator.clipboard.writeText(cell.textContent.trim());
            window.status = 'Copied: ' + cell.textContent.trim();
        });
    });
    // Quick filter
    var search = document.createElement('input');
    search.className = 'admin-custom-search';
    search.placeholder = 'Quick filter rows...';
    var table = document.querySelector('table');
    if (table && table.parentNode) {
        table.parentNode.insertBefore(search, table);
        search.addEventListener('input', function() {
            var val = this.value.toLowerCase();
            table.querySelectorAll('tbody tr').forEach(function(row) {
                row.style.display = row.textContent.toLowerCase().includes(val) ? '' : 'none';
            });
        });
    }
});
