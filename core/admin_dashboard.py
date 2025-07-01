from django.contrib.admin.views.decorators import staff_member_required
from django.shortcuts import render
from django.contrib.auth import get_user_model
from .models import Payment, Subscription
from django.db.models import Sum

@staff_member_required
def admin_dashboard(request):
    User = get_user_model()
    total_users = User.objects.count()
    total_revenue = Payment.objects.filter(status='confirmed').aggregate(total=Sum('amount'))['total'] or 0
    active_subscriptions = Subscription.objects.filter(is_active=True).count()
    context = {
        'total_users': total_users,
        'total_revenue': total_revenue,
        'active_subscriptions': active_subscriptions,
    }
    return render(request, 'admin_dashboard.html', context)
