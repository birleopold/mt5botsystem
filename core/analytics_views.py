from django.contrib.auth.decorators import login_required, user_passes_test
from django.http import JsonResponse
from django.db.models import Count, Sum
from django.shortcuts import render
from django.core.paginator import Paginator, EmptyPage, PageNotAnInteger
from .models import UserLevel, LicenseKey, SupportTicket, ForumPost, ExpertAdvisor, EAFile, Referral, Payment, AnalyticsEvent
from .trading_analytics import TradingMetrics, TradeDetail
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import datetime, timedelta
import json

@login_required
def user_analytics_data(request):
    user = request.user
    # Example: XP over time (last 30 days)
    today = timezone.now().date()
    xp_data = []
    for i in range(29, -1, -1):
        day = today - timedelta(days=i)
        xp = UserLevel.objects.filter(user=user, last_activity__date=day).values_list('xp', flat=True).first() or 0
        xp_data.append({'date': day.isoformat(), 'xp': xp})
    # Forum contributions
    forum_posts = ForumPost.objects.filter(user=user).count()
    
    # Trading performance - now using real trading metrics
    last_30_days = today - timedelta(days=30)
    metrics = TradingMetrics.objects.filter(user=user, date__gte=last_30_days)
    
    profit = metrics.aggregate(total=Sum('net_profit'))['total'] or 0
    
    # Calculate win rate
    total_trades = metrics.aggregate(trades=Sum('total_trades'))['trades'] or 0
    winning_trades = metrics.aggregate(wins=Sum('winning_trades'))['wins'] or 0
    
    win_rate = 0
    if total_trades > 0:
        win_rate = (winning_trades / total_trades) * 100
        
    # Get max drawdown
    drawdown = metrics.aggregate(max=Sum('max_drawdown'))['max'] or 0
    
    # EA usage
    ea_usage = list(LicenseKey.objects.filter(user=user).values('ea__name').annotate(count=Count('id')).order_by('-count'))
    
    # Referrals
    referral_count = Referral.objects.filter(referrer=user, referred_user__isnull=False).count()
    rewards = Payment.objects.filter(user=user, method='referral').aggregate(total=Sum('amount'))['total'] or 0
    
    return JsonResponse({
        'xp_over_time': xp_data,
        'forum_posts': forum_posts,
        'profit': float(profit),
        'win_rate': round(win_rate, 2),
        'drawdown': float(drawdown),
        'ea_usage': ea_usage,
        'referral_count': referral_count,
        'referral_rewards': float(rewards)
    })

@user_passes_test(lambda u: u.is_staff)
def admin_analytics_data(request):
    # User growth (last 30 days)
    today = timezone.now().date()
    user_model = get_user_model()
    growth = []
    for i in range(29, -1, -1):
        day = today - timedelta(days=i)
        count = user_model.objects.filter(date_joined__date=day).count()
        growth.append({'date': day.isoformat(), 'users': count})
    # License activations
    licenses = LicenseKey.objects.filter(created_at__gte=today - timedelta(days=29)).count()
    # Support tickets
    open_tickets = SupportTicket.objects.filter(status='open').count()
    closed_tickets = SupportTicket.objects.filter(status='closed').count()
    # Forum activity
    forum_posts = ForumPost.objects.filter(created_at__gte=today - timedelta(days=29)).count()
    # Revenue
    revenue = Payment.objects.aggregate(total=Sum('amount'))['total'] or 0
    # Churn/retention (dummy)
    active_users = user_model.objects.filter(is_active=True).count()
    churned_users = user_model.objects.filter(is_active=False).count()
    
    # Trading metrics
    last_30_days = today - timedelta(days=30)
    total_trades = TradeDetail.objects.filter(close_time__gte=last_30_days).count()
    profitable_trades = TradeDetail.objects.filter(close_time__gte=last_30_days, profit__gt=0).count()
    trading_profit = TradeDetail.objects.filter(close_time__gte=last_30_days).aggregate(total=Sum('profit'))['total'] or 0
    
    return JsonResponse({
        'user_growth': growth,
        'license_activations': licenses,
        'open_tickets': open_tickets,
        'closed_tickets': closed_tickets,
        'forum_posts': forum_posts,
        'revenue': float(revenue),
        'active_users': active_users,
        'churned_users': churned_users,
        'total_trades': total_trades,
        'profitable_trades': profitable_trades,
        'trading_profit': float(trading_profit)
    })

@user_passes_test(lambda u: u.is_staff)
def admin_analytics_data_chartjs(request):
    now = timezone.now()
    labels = []
    signups = []
    for i in range(11, -1, -1):
        month = (now - timedelta(days=now.day-1)).replace(day=1) - timedelta(days=30*i)
        next_month = (month + timedelta(days=32)).replace(day=1)
        label = month.strftime('%b %Y')
        count = User.objects.filter(date_joined__gte=month, date_joined__lt=next_month).count()
        labels.append(label)
        signups.append(count)
    return JsonResponse({'labels': labels[::-1], 'signups': signups[::-1]})
