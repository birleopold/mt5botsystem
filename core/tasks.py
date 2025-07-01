from django.utils import timezone
from datetime import timedelta
from django.db.models import F
from .models import Subscription, Notification
from .email_utils import send_html_email
from django.urls import reverse
from django.conf import settings


def check_expiring_subscriptions():
    """
    Check for subscriptions that are expiring soon and send reminders
    This function would be called by a task scheduler (like Celery)
    """
    # Define reminder periods (in days)
    reminder_days = [30, 14, 7, 3, 1]
    
    # Get current date
    now = timezone.now()
    
    # For each reminder period
    for days in reminder_days:
        # Calculate the target date
        target_date = now + timedelta(days=days)
        
        # Find subscriptions expiring on that date
        expiring_subscriptions = Subscription.objects.filter(
            is_active=True,
            end_date__date=target_date.date()
        ).select_related('user', 'plan')
        
        # Send reminder for each subscription
        for subscription in expiring_subscriptions:
            # Prepare context data for email
            context = {
                'user': subscription.user,
                'subscription': subscription,
                'days_remaining': days,
                'renewal_url': f"{settings.BASE_URL}{reverse('subscription_renew')}",
            }
            
            # Send email reminder
            subject = f"Your TheAutomata subscription expires in {days} days"
            send_html_email(
                subject=subject,
                template_name='emails/subscription_reminder.html',
                context=context,
                to_email=subscription.user.email
            )
            
            # Create notification in app
            Notification.objects.create(
                user=subscription.user,
                type='admin',
                message=f"Your subscription to {subscription.plan.name} plan expires in {days} days. Please renew soon to avoid service interruption.",
                url=reverse('subscription_renew')
            )
            
            # Log the reminder
            print(f"Sent {days}-day reminder to {subscription.user.email} for {subscription.plan.name} plan")


def handle_expired_subscriptions():
    """
    Process subscriptions that have just expired
    This function would be called by a task scheduler (like Celery)
    """
    # Get current date
    now = timezone.now()
    
    # Find subscriptions that expired but are still marked as active
    expired_subscriptions = Subscription.objects.filter(
        is_active=True,
        end_date__lt=now
    ).select_related('user', 'plan')
    
    # Process each expired subscription
    for subscription in expired_subscriptions:
        # Mark subscription as inactive
        subscription.is_active = False
        subscription.save()
        
        # Send expiration email
        context = {
            'user': subscription.user,
            'subscription': subscription,
            'renewal_url': f"{settings.BASE_URL}{reverse('subscription_renew')}",
        }
        
        send_html_email(
            subject="Your TheAutomata subscription has expired",
            template_name='emails/subscription_expired.html',
            context=context,
            to_email=subscription.user.email
        )
        
        # Create notification in app
        Notification.objects.create(
            user=subscription.user,
            type='admin',
            message=f"Your subscription to {subscription.plan.name} plan has expired. Please renew to continue using our services.",
            url=reverse('subscription_renew')
        )
        
        # Log the expiration
        print(f"Processed expired subscription for {subscription.user.email} - {subscription.plan.name} plan")
