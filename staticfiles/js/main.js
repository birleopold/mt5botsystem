// Mobile menu toggle, onboarding etc.
document.addEventListener('DOMContentLoaded', function() {
  // Onboarding modal close on outside click
  var modal = document.getElementById('onboarding-modal');
  if (modal) {
    modal.addEventListener('click', function(e) {
      if (e.target === modal) { modal.style.display = 'none'; }
    });
  }
});
