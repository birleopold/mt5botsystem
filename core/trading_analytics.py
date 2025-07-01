from django.db import models
from django.contrib.auth import get_user_model
from django.contrib.auth.models import User
from django.utils import timezone
from typing import Dict, List, Union, Any, Optional, cast, TypedDict, Literal
from decimal import Decimal
from datetime import date, datetime, timedelta
import json

class TradingMetrics(models.Model):
    """Model to store metrics from trading activities"""
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE, related_name='trading_metrics')
    date = models.DateField(default=timezone.now)
    
    # Trading performance metrics
    total_trades = models.IntegerField(default=0)
    winning_trades = models.IntegerField(default=0)
    losing_trades = models.IntegerField(default=0)
    profit_factor = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total_profit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    total_loss = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    net_profit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    
    # Risk metrics
    max_drawdown = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    avg_risk_reward = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    sharpe_ratio = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    
    # Strategy metrics
    strategy = models.CharField(max_length=100, blank=True)
    timeframe = models.CharField(max_length=20, blank=True)
    traded_pairs = models.JSONField(default=list)
    
    class Meta:
        verbose_name = "Trading Metrics"
        verbose_name_plural = "Trading Metrics"
        ordering = ['-date']
        
    def __str__(self):
        return f"{self.user.username} - {self.date} - {self.net_profit}"
    
    @property
    def win_rate(self):
        """Calculate win rate percentage"""
        if self.total_trades > 0:
            return (self.winning_trades / self.total_trades) * 100
        return 0
    
    @property
    def loss_rate(self):
        """Calculate loss rate percentage"""
        if self.total_trades > 0:
            return (self.losing_trades / self.total_trades) * 100
        return 0


class TradeDetail(models.Model):
    """Model to store individual trade details"""
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE, related_name='trade_details')
    
    # Trade identification
    ticket_id = models.CharField(max_length=50)
    symbol = models.CharField(max_length=20)
    strategy = models.CharField(max_length=100, blank=True)
    bot_name = models.CharField(max_length=100, blank=True)
    
    # Trade parameters
    trade_type = models.CharField(max_length=10, choices=[('BUY', 'Buy'), ('SELL', 'Sell')])
    open_time = models.DateTimeField()
    close_time = models.DateTimeField(null=True, blank=True)
    
    # Trade financials
    open_price = models.DecimalField(max_digits=12, decimal_places=5)
    close_price = models.DecimalField(max_digits=12, decimal_places=5, null=True, blank=True)
    lot_size = models.DecimalField(max_digits=10, decimal_places=2)
    stop_loss = models.DecimalField(max_digits=12, decimal_places=5, null=True, blank=True)
    take_profit = models.DecimalField(max_digits=12, decimal_places=5, null=True, blank=True)
    profit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    
    # Status
    status = models.CharField(max_length=10, choices=[
        ('OPEN', 'Open'),
        ('CLOSED', 'Closed'),
        ('CANCELED', 'Canceled')
    ])
    
    # Additional information
    timeframe = models.CharField(max_length=10, blank=True)  # M1, M5, H1, D1, etc.
    entry_reason = models.TextField(blank=True)
    exit_reason = models.TextField(blank=True)
    
    class Meta:
        ordering = ['-open_time']
        
    def __str__(self):
        return f"{self.user.username} - {self.symbol} - {self.ticket_id}"
    
    @property
    def is_winner(self):
        """Check if trade was profitable"""
        return self.profit > 0
    
    @property
    def duration(self):
        """Calculate trade duration"""
        if self.close_time and self.open_time:
            return self.close_time - self.open_time
        return None


def aggregate_daily_metrics(user: User, date: Optional[date] = None) -> TradingMetrics:
    """
    Calculate aggregated metrics for a specific day
    
    Args:
        user: User object
        date: Date to aggregate metrics for (defaults to today)
    
    Returns:
        A TradingMetrics instance with aggregated metrics
    """
    if date is None:
        date = timezone.now().date()
    
    # Get all closed trades for the user on the specified date
    trades = TradeDetail.objects.filter(
        user=user,
        status='CLOSED',
        close_time__date=date
    )
    
    # Initialize metrics
    total_trades = trades.count()
    winning_trades = trades.filter(profit__gt=0).count()
    losing_trades = trades.filter(profit__lte=0).count()
    
    total_profit = sum(t.profit for t in trades.filter(profit__gt=0))
    total_loss = abs(sum(t.profit for t in trades.filter(profit__lte=0)))
    net_profit = total_profit - total_loss
    
    # Calculate profit factor
    profit_factor = total_profit / total_loss if total_loss > 0 else total_profit
    
    # Get unique strategies
    strategies = set(t.strategy for t in trades if t.strategy)
    
    # Get unique pairs
    pairs = list(set(t.symbol for t in trades))
    
    # Create or update metrics record
    metrics, created = TradingMetrics.objects.update_or_create(
        user=user,
        date=date,
        defaults={
            'total_trades': total_trades,
            'winning_trades': winning_trades,
            'losing_trades': losing_trades,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'net_profit': net_profit,
            'profit_factor': profit_factor,
            'strategy': ', '.join(strategies) if strategies else '',
            'traded_pairs': pairs,
        }
    )
    
    return metrics
