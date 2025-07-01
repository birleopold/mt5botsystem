from django.shortcuts import render
from django.contrib.auth.decorators import login_required
from django.http import JsonResponse, HttpRequest, HttpResponse
from django.db.models import Sum, Avg, Max, Min, Count, F, Q, ExpressionWrapper, DecimalField, QuerySet
from django.utils import timezone
from datetime import timedelta, date
from typing import Dict, List, Union, Any, Optional, Tuple, cast
from django.contrib.auth.models import User
from .models import AnalyticsEvent
from .trading_analytics import TradingMetrics, TradeDetail


@login_required
def trading_dashboard(request: HttpRequest) -> HttpResponse:
    """Render the user's trading analytics dashboard"""
    user: User = cast(User, request.user)
    
    # Get data for summary cards
    today = timezone.now().date()
    last_30_days = today - timedelta(days=30)
    
    # Get the user's trading metrics for the last 30 days
    metrics = TradingMetrics.objects.filter(
        user=user,
        date__gte=last_30_days
    ).order_by('-date')
    
    # Calculate summary statistics
    total_profit = metrics.aggregate(sum=Sum('net_profit'))['sum'] or 0
    win_rate = 0
    total_trades = metrics.aggregate(sum=Sum('total_trades'))['sum'] or 0
    winning_trades = metrics.aggregate(sum=Sum('winning_trades'))['sum'] or 0
    
    if total_trades > 0:
        win_rate = (winning_trades / total_trades) * 100
    
    # Get latest trades for trade history table
    recent_trades = TradeDetail.objects.filter(
        user=user
    ).order_by('-close_time')[:10]
    
    # Get top performing symbols
    top_symbols = TradeDetail.objects.filter(
        user=user,
        status='CLOSED',
        close_time__gte=last_30_days
    ).values('symbol').annotate(
        total_profit=Sum('profit'),
        trade_count=Count('id')
    ).order_by('-total_profit')[:5]
    
    # Record analytics event for page view
    AnalyticsEvent.objects.create(
        user=user,
        event_type='view_trading_dashboard'
    )
    
    context = {
        'total_profit': total_profit,
        'win_rate': round(win_rate, 2),
        'total_trades': total_trades,
        'recent_trades': recent_trades,
        'top_symbols': top_symbols,
        'metrics': metrics[:30],  # Last 30 days of metrics
    }
    
    return render(request, 'trading/dashboard.html', context)


@login_required
def trading_metrics_json(request: HttpRequest) -> JsonResponse:
    """Return JSON data for trading metrics charts"""
    user: User = cast(User, request.user)
    
    # Get date range from query parameters, default to last 30 days
    days = int(request.GET.get('days', 30))
    today = timezone.now().date()
    start_date = today - timedelta(days=days)
    
    # Get daily metrics
    daily_metrics = TradingMetrics.objects.filter(
        user=user,
        date__gte=start_date
    ).order_by('date')
    
    # Prepare data for charts
    labels = []
    profit_data = []
    trade_count_data = []
    win_rate_data = []
    
    for metric in daily_metrics:
        labels.append(metric.date.strftime('%Y-%m-%d'))
        profit_data.append(float(metric.net_profit))
        trade_count_data.append(metric.total_trades)
        
        # Calculate win rate
        win_rate = 0
        if metric.total_trades > 0:
            win_rate = (metric.winning_trades / metric.total_trades) * 100
        win_rate_data.append(round(win_rate, 2))
    
    return JsonResponse({
        'labels': labels,
        'profit_data': profit_data,
        'trade_count_data': trade_count_data,
        'win_rate_data': win_rate_data,
    })


@login_required
def trade_details(request: HttpRequest) -> HttpResponse:
    """View for detailed trade history with filtering"""
    user: User = cast(User, request.user)
    
    # Get filter parameters
    symbol = request.GET.get('symbol', '')
    strategy = request.GET.get('strategy', '')
    result = request.GET.get('result', '')
    days = int(request.GET.get('days', 30))
    
    # Base queryset
    trades = TradeDetail.objects.filter(user=user)
    
    # Apply filters
    if symbol:
        trades = trades.filter(symbol=symbol)
    
    if strategy:
        trades = trades.filter(strategy=strategy)
    
    if result == 'win':
        trades = trades.filter(profit__gt=0)
    elif result == 'loss':
        trades = trades.filter(profit__lte=0)
    
    if days > 0:
        start_date = timezone.now() - timedelta(days=days)
        trades = trades.filter(open_time__gte=start_date)
    
    # Order by close time descending
    trades = trades.order_by('-close_time')
    
    # Get distinct symbols and strategies for filters
    symbols = TradeDetail.objects.filter(user=user).values_list('symbol', flat=True).distinct()
    strategies = TradeDetail.objects.filter(user=user).values_list('strategy', flat=True).distinct()
    
    context = {
        'trades': trades,
        'symbols': symbols,
        'strategies': strategies,
        'applied_filters': {
            'symbol': symbol,
            'strategy': strategy,
            'result': result,
            'days': days,
        }
    }
    
    return render(request, 'trading/trade_details.html', context)


@login_required
def symbol_performance(request: HttpRequest) -> HttpResponse:
    """View for symbol-specific performance analysis"""
    user: User = cast(User, request.user)
    
    # Get filter parameters
    days = int(request.GET.get('days', 30))
    today = timezone.now().date()
    start_date = today - timedelta(days=days)
    
    # Get symbol performance data
    symbols = TradeDetail.objects.filter(
        user=user,
        status='CLOSED',
        close_time__date__gte=start_date
    ).values('symbol').annotate(
        total_profit=Sum('profit'),
        trade_count=Count('id'),
        win_count=Count('id', filter=Q(profit__gt=0)),
        loss_count=Count('id', filter=Q(profit__lte=0)),
        avg_profit=Avg('profit', filter=Q(profit__gt=0)),
        avg_loss=Avg('profit', filter=Q(profit__lte=0)),
        max_profit=Max('profit'),
        max_loss=Min('profit')
    ).order_by('-total_profit')
    
    # Calculate win rate for each symbol
    for symbol in symbols:
        if symbol['trade_count'] > 0:
            symbol['win_rate'] = (symbol['win_count'] / symbol['trade_count']) * 100
        else:
            symbol['win_rate'] = 0
    
    context = {
        'symbols': symbols,
        'days': days,
    }
    
    return render(request, 'trading/symbol_performance.html', context)
