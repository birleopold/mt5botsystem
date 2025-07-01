/**
 * Theme Toggle Handler for MetaTrader 5 SaaS Platform
 * Manages theme switching between light and dark modes
 */

document.addEventListener('DOMContentLoaded', function() {
    const themeToggle = document.getElementById('themeToggle');
    const prefersDarkScheme = window.matchMedia('(prefers-color-scheme: dark)');
    
    // Initialize theme based on user preference or system preference
    initializeTheme();
    
    // Add event listener to the theme toggle button
    if (themeToggle) {
        themeToggle.addEventListener('click', function() {
            toggleTheme();
        });
    }
    
    /**
     * Initialize theme based on saved preference or system preference
     */
    function initializeTheme() {
        const savedTheme = localStorage.getItem('theme');
        
        if (savedTheme === 'dark') {
            document.body.classList.add('dark-mode');
        } else if (savedTheme === 'light') {
            document.body.classList.remove('dark-mode');
        } else if (prefersDarkScheme.matches) {
            // If no saved preference but system prefers dark
            document.body.classList.add('dark-mode');
            localStorage.setItem('theme', 'dark');
        }
        
        // Update chart colors if any charts exist
        updateChartsForTheme();
    }
    
    /**
     * Toggle between light and dark themes
     */
    function toggleTheme() {
        if (document.body.classList.contains('dark-mode')) {
            document.body.classList.remove('dark-mode');
            localStorage.setItem('theme', 'light');
        } else {
            document.body.classList.add('dark-mode');
            localStorage.setItem('theme', 'dark');
        }
        
        // Update chart colors if any charts exist
        updateChartsForTheme();
    }
    
    /**
     * Update Chart.js charts to match the current theme
     */
    function updateChartsForTheme() {
        if (window.Chart) {
            const isDarkMode = document.body.classList.contains('dark-mode');
            
            // Update Chart.js defaults
            Chart.defaults.color = isDarkMode ? '#adb5bd' : '#666';
            Chart.defaults.borderColor = isDarkMode ? '#343a40' : '#ddd';
            
            // Refresh any existing charts
            Chart.instances.forEach(chart => {
                // Update grid lines
                if (chart.config.options.scales && chart.config.options.scales.x) {
                    chart.config.options.scales.x.grid.color = isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(0, 0, 0, 0.1)';
                }
                
                if (chart.config.options.scales && chart.config.options.scales.y) {
                    chart.config.options.scales.y.grid.color = isDarkMode ? 'rgba(255, 255, 255, 0.1)' : 'rgba(0, 0, 0, 0.1)';
                }
                
                // Update chart
                chart.update();
            });
        }
    }
    
    // Listen for system preference changes
    prefersDarkScheme.addEventListener('change', e => {
        const savedTheme = localStorage.getItem('theme');
        
        // Only change if user hasn't explicitly set a preference
        if (!savedTheme) {
            if (e.matches) {
                document.body.classList.add('dark-mode');
            } else {
                document.body.classList.remove('dark-mode');
            }
            
            updateChartsForTheme();
        }
    });
});
