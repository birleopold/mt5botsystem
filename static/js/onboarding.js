/**
 * Interactive Onboarding Tour for MT5 SaaS Platform
 * Uses Shepherd.js for guided tours
 */

class OnboardingTour {
  constructor() {
    this.tour = new Shepherd.Tour({
      defaultStepOptions: {
        cancelIcon: {
          enabled: true
        },
        classes: 'shepherd-theme-custom',
        scrollTo: { behavior: 'smooth', block: 'center' }
      },
      useModalOverlay: true
    });

    this.setupTourSteps();
    this.setupEventListeners();
  }

  setupEventListeners() {
    // Save tour progress in localStorage
    this.tour.on('complete', () => {
      localStorage.setItem('onboardingCompleted', 'true');
      
      // Send to server that onboarding is complete
      fetch('/onboarding/complete/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRFToken': this.getCsrfToken()
        },
        body: JSON.stringify({ completed: true })
      });
    });

    // Continue from last step if tour was interrupted
    this.tour.on('show', (e) => {
      localStorage.setItem('currentTourStep', e.step.id);
    });
  }

  getCsrfToken() {
    return document.querySelector('[name=csrfmiddlewaretoken]').value;
  }

  setupTourSteps() {
    // Step 1: Welcome
    this.tour.addStep({
      id: 'welcome',
      title: 'Welcome to MT5 SaaS Platform!',
      text: `<p>Let's take a quick tour to help you get the most out of our platform.</p>`,
      buttons: [
        {
          text: 'Skip Tour',
          action: this.tour.complete
        },
        {
          text: 'Next',
          action: this.tour.next
        }
      ]
    });

    // Step 2: Dashboard
    this.tour.addStep({
      id: 'dashboard',
      title: 'Your Dashboard',
      text: `<p>This is your personal dashboard where you can see all your active subscriptions, bots, and trading performance.</p>`,
      attachTo: {
        element: '.navbar-nav a[href*="dashboard"]',
        on: 'bottom'
      },
      buttons: [
        {
          text: 'Back',
          action: this.tour.back
        },
        {
          text: 'Next',
          action: this.tour.next
        }
      ]
    });

    // Step 3: Trading Analytics
    this.tour.addStep({
      id: 'trading-analytics',
      title: 'Trading Analytics',
      text: `<p>Track your trading performance with detailed analytics and insights that help you improve your strategies.</p>`,
      attachTo: {
        element: '.navbar-nav a[href*="trading_dashboard"]',
        on: 'bottom'
      },
      buttons: [
        {
          text: 'Back',
          action: this.tour.back
        },
        {
          text: 'Next',
          action: this.tour.next
        }
      ]
    });

    // Step 4: Subscription Plans
    this.tour.addStep({
      id: 'plans',
      title: 'Subscription Plans',
      text: `<p>Browse our different subscription plans to access premium trading bots and features.</p>`,
      attachTo: {
        element: '.navbar-nav a[href*="plan_list"]',
        on: 'bottom'
      },
      buttons: [
        {
          text: 'Back',
          action: this.tour.back
        },
        {
          text: 'Next',
          action: this.tour.next
        }
      ]
    });

    // Step 5: Theme Toggle
    this.tour.addStep({
      id: 'theme-toggle',
      title: 'Dark/Light Mode',
      text: `<p>Toggle between dark and light modes to customize your experience based on your preference.</p>`,
      attachTo: {
        element: '#themeToggle',
        on: 'bottom'
      },
      buttons: [
        {
          text: 'Back',
          action: this.tour.back
        },
        {
          text: 'Next',
          action: this.tour.next
        }
      ]
    });

    // Step 6: Notifications
    this.tour.addStep({
      id: 'notifications',
      title: 'Notifications',
      text: `<p>Stay updated with important alerts, announcements, and updates about your account and trading bots.</p>`,
      attachTo: {
        element: '#notifBell',
        on: 'bottom'
      },
      buttons: [
        {
          text: 'Back',
          action: this.tour.back
        },
        {
          text: 'Next',
          action: this.tour.next
        }
      ]
    });

    // Step 7: Mobile Experience
    this.tour.addStep({
      id: 'pwa',
      title: 'Mobile Experience',
      text: `<p>Our platform is also a Progressive Web App (PWA). You can install it on your mobile device for a better experience by tapping "Add to Home Screen" in your browser menu.</p>`,
      buttons: [
        {
          text: 'Back',
          action: this.tour.back
        },
        {
          text: 'Finish Tour',
          action: this.tour.complete
        }
      ]
    });
  }

  start() {
    // Check if user has completed onboarding
    if (localStorage.getItem('onboardingCompleted') === 'true') {
      return;
    }

    // Resume from last step if available
    const lastStep = localStorage.getItem('currentTourStep');
    if (lastStep) {
      this.tour.show(lastStep);
    } else {
      this.tour.start();
    }
  }
}

// Initialize and start tour when DOM is fully loaded
document.addEventListener('DOMContentLoaded', () => {
  // Only show tour for authenticated users who haven't completed onboarding
  const isAuthenticated = document.body.classList.contains('authenticated-user');
  
  if (isAuthenticated && window.Shepherd) {
    const onboardingTour = new OnboardingTour();
    
    // Delay tour start to ensure page is fully rendered
    setTimeout(() => {
      onboardingTour.start();
    }, 1000);
  }
});
