from django.contrib.admin.views.decorators import staff_member_required
from django.shortcuts import render
from core.models import SocialShareEvent
from django.db.models import Count

@staff_member_required
def share_analytics_dashboard(request):
    # Top referrers
    top_referrers = (
        SocialShareEvent.objects.values('user__username')
        .annotate(total=Count('id'))
        .order_by('-total')[:10]
    )
    # Shares by platform
    shares_by_platform = (
        SocialShareEvent.objects.values('platform')
        .annotate(total=Count('id'))
        .order_by('-total')
    )
    # Recent shares (for audit)
    recent_shares = SocialShareEvent.objects.select_related('user').order_by('-shared_at')[:25]
    return render(request, 'admin_share_analytics.html', {
        'top_referrers': top_referrers,
        'shares_by_platform': shares_by_platform,
        'recent_shares': recent_shares,
    })
