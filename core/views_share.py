from django.views.decorators.csrf import csrf_exempt
from django.http import JsonResponse
from django.contrib.auth.decorators import login_required
from django.utils import timezone
import json
from core.models import SocialShareEvent, ShareReward, Notification
from django.conf import settings

@csrf_exempt
@login_required
def share_event(request):
    if request.method != 'POST':
        return JsonResponse({'error': 'POST required'}, status=405)
    try:
        data = json.loads(request.body)
        platform = data.get('platform')
        referral_url = data.get('referral_url')
        message = data.get('message', '')
        event = SocialShareEvent.objects.create(
            user=request.user,
            platform=platform,
            referral_url=referral_url,
            message=message,
            shared_at=timezone.now()
        )
        # Grant reward for sharing (one per event)
        ShareReward.objects.create(
            user=request.user,
            event=event,
            reward_type='share',
            reward_value=1
        )
        # Notify user of reward (best practice)
        Notification.objects.create(
            user=request.user,
            message='You earned a reward for sharing on ' + platform + '!',
            type='success',
            url='',
        )
        # Milestone notification (e.g. every 5 shares)
        share_count = SocialShareEvent.objects.filter(user=request.user).count()
        if share_count % 5 == 0:
            Notification.objects.create(
                user=request.user,
                message=f'Congrats! You have shared {share_count} times and earned a bonus!',
                type='success',
                url='',
            )
        return JsonResponse({'status': 'ok', 'rewarded': True})
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=400)
