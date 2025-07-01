from django.contrib.admin.views.decorators import staff_member_required
from django.shortcuts import render
from django.contrib.auth import get_user_model
from .models import Payment, Subscription
from django.db.models import Sum
from django.utils import timezone
from datetime import timedelta

@staff_member_required
def admin_dashboard_extra(request):
    User = get_user_model()
    now = timezone.now()
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)

    total_users = User.objects.count()
    new_users = User.objects.filter(date_joined__gte=week_ago).count()

    total_revenue = Payment.objects.filter(status='confirmed').aggregate(total=Sum('amount'))['total'] or 0
    new_revenue = Payment.objects.filter(status='confirmed', created_at__gte=week_ago).aggregate(total=Sum('amount'))['total'] or 0

    active_subscriptions = Subscription.objects.filter(is_active=True).count()

    # Revenue graph (last 30 days)
    revenue_by_day = (
        Payment.objects.filter(status='confirmed', created_at__gte=month_ago)
        .extra({'day': "date(created_at)"})
        .values('day')
        .annotate(total=Sum('amount'))
        .order_by('day')
    )
    revenue_dates = [entry['day'] if isinstance(entry['day'], str) else entry['day'].strftime('%Y-%m-%d') for entry in revenue_by_day]
    revenue_values = [float(entry['total']) for entry in revenue_by_day]

    context = {
        'total_users': total_users,
        'new_users': new_users,
        'total_revenue': total_revenue,
        'new_revenue': new_revenue,
        'active_subscriptions': active_subscriptions,
        'revenue_dates': revenue_dates,
        'revenue_values': revenue_values,
    }
    return render(request, 'admin_dashboard_extra.html', context)
