from django.contrib.admin.views.decorators import staff_member_required
from django.shortcuts import render
from django.db.models import Count, Sum, Q
from core.models import User, Subscription, LicenseKey, Payment
from django.utils import timezone
from datetime import timedelta

@staff_member_required
def analytics_dashboard(request):
    now = timezone.now()
    last_30 = now - timedelta(days=30)
    context = {
        'total_users': User.objects.count(),
        'active_users': User.objects.filter(last_login__gte=last_30).count(),
        'subscriptions_active': Subscription.objects.filter(is_active=True).count(),
        'subscriptions_expired': Subscription.objects.filter(is_active=False, end_date__lt=now).count(),
        'subscriptions_cancelled': Subscription.objects.filter(is_active=False, end_date__isnull=False).count(),
        'licenses_issued': LicenseKey.objects.count(),
        'licenses_active': LicenseKey.objects.filter(status='active').count(),
        'licenses_expired': LicenseKey.objects.filter(status='revoked').count(),
        'revenue_total': Payment.objects.filter(status='paid').aggregate(total=Sum('amount'))['total'] or 0,
        'revenue_month': Payment.objects.filter(status='paid', created_at__gte=now.replace(day=1)).aggregate(total=Sum('amount'))['total'] or 0,
        'signups_last_30': User.objects.filter(date_joined__gte=last_30).count(),
        'churn_last_30': Subscription.objects.filter(is_active=False, end_date__gte=last_30).count(),
    }
    return render(request, 'admin_analytics.html', context)
