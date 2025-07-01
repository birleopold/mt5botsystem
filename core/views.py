from django.shortcuts import render, redirect
from django.contrib.auth.forms import UserCreationForm
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from .models import SubscriptionPlan, Payment, Subscription, Referral, ReferralReward, Ticket, ReferralConfig, Notification, UserProfile, Badge, UserBadge, AnalyticsEvent, UserLevel, SocialShareEvent, SupportTicket, ForumCategory, ForumTopic, ForumPost, ExpertAdvisor, EAFile, LicenseKey, AuditLog, ShareReward
from django.http import Http404, JsonResponse
from .forms import ManualPaymentForm
from django.conf import settings
from django.views.decorators.csrf import csrf_exempt, csrf_protect
from .coinbase import create_charge
from .binance import generate_binance_payment_request
import json
from django.core.mail import send_mail
from django.urls import reverse
import secrets
from django.contrib.auth import login as auth_login
from datetime import timedelta
from django.utils import timezone
from django.views.decorators.http import require_POST, require_http_methods
from django.utils.timezone import now
from django.db.models import Count
from django.db import models
from django.contrib.auth.models import User
import datetime
from rest_framework.authtoken.models import Token

# Create your views here.

def register(request):
    if request.method == 'POST':
        form = UserCreationForm(request.POST)
        if form.is_valid():
            user = form.save()
            ref_code = request.GET.get('ref') or request.POST.get('ref')
            if ref_code:
                try:
                    referral = Referral.objects.get(code=ref_code)
                    referral.referred_user = user
                    referral.save()
                    check_and_grant_referral_reward(referral.referrer)
                except Referral.DoesNotExist:
                    pass
            messages.success(request, 'Registration successful. Please log in.')
            return redirect('login')
    else:
        form = UserCreationForm()
    return render(request, 'registration/register.html', {'form': form})

@login_required
def dashboard(request):
    from .models import Subscription, Payment, ExpertAdvisor, EAFile, LicenseKey, ShareReward
    profile = get_or_create_userprofile(request.user)
    show_onboarding = not profile.onboarding_complete
    # Award "First Login" badge
    award_badge(request.user, "First Login")
    track_event(request.user, "dashboard_view")
    AnalyticsEvent.objects.create(user=request.user, event_type="dashboard_view")
    ul = add_xp(request.user, 5, reason="dashboard_view")
    subscriptions = Subscription.objects.filter(user=request.user, is_active=True)
    plans = [sub.plan for sub in subscriptions]
    payments = Payment.objects.filter(user=request.user).order_by('-created_at')[:10]
    referral = get_user_referral(request.user)
    referred_count = get_referred_count(request.user)
    rewards = ShareReward.objects.filter(user=request.user).order_by('-rewarded_at')[:10]
    tickets = Ticket.objects.filter(user=request.user).order_by('-created_at')[:5]
    notifications = Notification.objects.filter(user=request.user).order_by('-created_at')
    unread_notes = notifications.filter(is_read=False).count()
    notifications = notifications[:10]
    eas = ExpertAdvisor.objects.all()  # Or filter by another method as appropriate
    licenses = LicenseKey.objects.filter(user=request.user)
    ea_files = EAFile.objects.filter(ea__in=eas)
    badges = UserBadge.objects.filter(user=request.user).select_related('badge')
    return render(request, 'dashboard.html', {
        'subscriptions': subscriptions,
        'payments': payments,
        'referral': referral,
        'referred_count': referred_count,
        'rewards': rewards,
        'tickets': tickets,
        'notifications': notifications,
        'unread_notes': unread_notes,
        'badges': badges,
        'show_onboarding': show_onboarding,
        'userlevel': ul,
        'eas': eas,
        'licenses': licenses,
        'ea_files': ea_files,
    })

@login_required
def submit_ticket(request):
    from django.contrib import messages
    if request.method == 'POST':
        subject = request.POST.get('subject')
        message = request.POST.get('message')
        if subject and message:
            Ticket.objects.create(user=request.user, subject=subject, message=message)
            messages.success(request, 'Your support ticket has been submitted.')
            return redirect('dashboard')
        else:
            messages.error(request, 'Please fill in all fields.')
    return render(request, 'submit_ticket.html')

@login_required
def plan_list(request):
    plans = SubscriptionPlan.objects.filter(is_active=True)
    return render(request, 'plans.html', {'plans': plans})

@login_required
def checkout(request, plan_id):
    try:
        plan = SubscriptionPlan.objects.get(id=plan_id, is_active=True)
    except SubscriptionPlan.DoesNotExist:
        raise Http404('Plan not found')
    if request.method == 'POST':
        method = request.POST.get('method')
        if method == 'cash':
            return redirect('manual_payment', plan_id=plan.id)
    return render(request, 'checkout.html', {'plan': plan})

@login_required
def manual_payment(request, plan_id):
    try:
        plan = SubscriptionPlan.objects.get(id=plan_id, is_active=True)
    except SubscriptionPlan.DoesNotExist:
        raise Http404('Plan not found')
    if request.method == 'POST':
        form = ManualPaymentForm(request.POST, request.FILES)
        if form.is_valid():
            payment = form.save(commit=False)
            payment.user = request.user
            payment.plan = plan
            payment.amount = plan.price
            payment.method = 'cash'
            payment.status = 'pending'
            payment.save()
            return redirect('payment_status', payment_id=payment.id)
    else:
        form = ManualPaymentForm()
    return render(request, 'manual_payment.html', {'plan': plan, 'form': form})

@login_required
def payment_status(request, payment_id):
    try:
        payment = Payment.objects.get(id=payment_id, user=request.user)
    except Payment.DoesNotExist:
        raise Http404('Payment not found')
    return render(request, 'payment_status.html', {'payment': payment})

def activate_subscription(user, plan, payment):
    from .models import Subscription
    sub, created = Subscription.objects.get_or_create(
        user=user,
        plan=plan
    )
    if not created:
        sub.is_active = True
        sub.save()
    # Optionally, send email notification
    send_mail(
        subject='Subscription Activated',
        message=f'Your subscription for {plan.name} is now active. Thank you for your payment!',
        from_email=None,
        recipient_list=[user.email],
        fail_silently=True,
    )
    # Optionally, notify admin
    send_mail(
        subject='New Subscription Activated',
        message=f'{user.username} activated {plan.name} via {payment.method}.',
        from_email=None,
        recipient_list=['admin@example.com'],
        fail_silently=True,
    )

@csrf_exempt
def coinbase_webhook(request):
    payload = json.loads(request.body.decode('utf-8'))
    event_type = payload.get('event', {}).get('type')
    charge_id = payload.get('event', {}).get('data', {}).get('id')
    if event_type == 'charge:confirmed' and charge_id:
        try:
            payment = Payment.objects.get(transaction_id=charge_id, method='crypto', notes='Coinbase')
            payment.status = 'confirmed'
            payment.save()
            activate_subscription(payment.user, payment.plan, payment)
            confirm_payment_badges(payment.user)
        except Payment.DoesNotExist:
            pass
    return HttpResponse(status=200)

@csrf_protect
def contact(request):
    from django.contrib import messages
    if request.method == 'POST':
        email = request.POST.get('email')
        message = request.POST.get('message')
        if email and message:
            send_mail(
                subject='Support Request',
                message=f'From: {email}\n\n{message}',
                from_email=None,
                recipient_list=['support@example.com'],
                fail_silently=True,
            )
            messages.success(request, 'Your message has been sent. We will get back to you soon.')
        else:
            messages.error(request, 'Please fill in all fields.')
    return render(request, 'contact.html')

def notify(user, message, type='info'):
    Notification.objects.create(user=user, message=message, type=type)

def award_badge(user, badge_name):
    badge = Badge.objects.filter(name=badge_name).first()
    if badge and not UserBadge.objects.filter(user=user, badge=badge).exists():
        UserBadge.objects.create(user=user, badge=badge)
        AnalyticsEvent.objects.create(user=user, event_type="badge_awarded", event_value=badge_name)

def track_event(user, event_type, event_value=""):
    AnalyticsEvent.objects.create(user=user, event_type=event_type, event_value=event_value)

def check_and_grant_referral_reward(referrer):
    config = ReferralConfig.objects.filter(active=True).order_by('-reward_threshold').first()
    if not config:
        return
    referred_count = Referral.objects.filter(referrer=referrer, referred_user__isnull=False).count()
    reward_already = ReferralReward.objects.filter(user=referrer, reward_type=config.reward_type, reward_value=config.reward_value).count()
    if referred_count >= config.reward_threshold and reward_already < referred_count // config.reward_threshold:
        reward = ReferralReward.objects.create(
            user=referrer,
            referral=Referral.objects.filter(referrer=referrer, referred_user__isnull=False).last(),
            reward_type=config.reward_type,
            reward_value=config.reward_value,
        )
        # Automate reward: extend subscription or apply discount
        from .models import Subscription
        if config.reward_type == 'free_month':
            sub = Subscription.objects.filter(user=referrer, is_active=True).order_by('-end_date').first()
            from datetime import timedelta
            if sub:
                sub.end_date = sub.end_date + timedelta(days=30*int(config.reward_value or '1'))
                sub.save()
                notify(referrer, f"Your subscription was extended by {config.reward_value or 1} month(s) for referring users!", type='success')
        elif config.reward_type == 'discount':
            notify(referrer, f"You earned a discount: {config.reward_value}! Contact support to redeem.", type='success')
        else:
            notify(referrer, f"You earned a referral reward!", type='success')
        # Award referral badges
        if referred_count == 1:
            award_badge(referrer, "First Referral")
        if referred_count >= 5:
            award_badge(referrer, "5 Referrals")
        if referred_count >= 10:
            award_badge(referrer, "Referral Champion")
        add_xp(referrer, 20, reason="referral")
        AnalyticsEvent.objects.create(user=referrer, event_type="referral_reward", event_value=f"{referred_count}")
        return reward

def confirm_payment_badges(user):
    paid_count = Payment.objects.filter(user=user, status='confirmed').count()
    if paid_count == 1:
        award_badge(user, "First Payment")
    if paid_count >= 5:
        award_badge(user, "5 Payments")
    add_xp(user, 15, reason="payment")
    AnalyticsEvent.objects.create(user=user, event_type="payment_confirmed", event_value=str(paid_count))

@login_required
def notifications(request):
    notes = Notification.objects.filter(user=request.user).order_by('-created_at')
    return render(request, 'notifications.html', {'notifications': notes})

@login_required
@require_POST
def dismiss_notification(request, note_id):
    Notification.objects.filter(user=request.user, id=note_id).update(read=True)
    return redirect('notifications')

def get_advanced_notifications(user):
    notifications = []
    # Expiring subscription
    from datetime import timedelta
    from .models import Subscription
    soon = timezone.now() + timedelta(days=5)
    expiring = Subscription.objects.filter(user=user, is_active=True, end_date__lte=soon, end_date__gte=timezone.now())
    if expiring.exists():
        notifications.append("Your subscription is expiring soon! Renew to avoid interruption.")
    # New features (hardcoded example)
    notifications.append(" New: Referral rewards and in-app notifications are now live!")
    return notifications

def get_or_create_userprofile(user):
    profile, created = UserProfile.objects.get_or_create(user=user)
    if created or not profile.first_login:
        profile.first_login = now()
        profile.save()
    return profile

def get_or_create_userlevel(user):
    ul, _ = UserLevel.objects.get_or_create(user=user)
    return ul

# --- XP sources and streak incentives ---
def add_xp(user, amount=10, reason=None):
    ul = get_or_create_userlevel(user)
    # Double XP event logic (growth experiment)
    from django.utils.timezone import now as tz_now
    now = tz_now()
    double_xp = False
    # Example: Double XP on weekends
    if now.weekday() in [5, 6]:
        double_xp = True
    # Example: Referral contest period (April 21-28, 2025)
    if now.date() >= datetime.date(2025, 4, 21) and now.date() <= datetime.date(2025, 4, 28):
        double_xp = True
    if double_xp:
        amount *= 2
    ul.xp += amount
    # Streak logic: +1 if last_activity was yesterday, else reset
    if ul.last_activity:
        delta = (now.date() - ul.last_activity.date()).days
        if delta == 1:
            ul.streak += 1
        elif delta > 1:
            ul.streak = 1
    else:
        ul.streak = 1
    ul.last_activity = now
    # Level up
    while ul.xp >= ul.xp_for_next_level():
        ul.xp -= ul.xp_for_next_level()
        ul.level += 1
        award_badge(user, f"Level {ul.level}")
    ul.save()
    if reason:
        AnalyticsEvent.objects.create(user=user, event_type="xp_gain", event_value=f"{amount}:{reason}")
    return ul

# --- Admin analytics summary view ---
from django.db.models import Count, Sum
from django.contrib.admin.views.decorators import staff_member_required

@staff_member_required
def admin_analytics_summary(request):
    user_count = get_user_model().objects.count()
    active_users = AnalyticsEvent.objects.filter(event_type="dashboard_view", created_at__gte=timezone.now()-timezone.timedelta(days=7)).values('user').distinct().count()
    top_referrers = Referral.objects.values('referrer__username').annotate(total=Count('referred_user')).order_by('-total')[:5]
    badge_counts = UserBadge.objects.values('badge__name').annotate(count=Count('id')).order_by('-count')[:5]
    level_dist = UserLevel.objects.values('level').annotate(count=Count('id')).order_by('-level')
    return render(request, 'admin_analytics_summary.html', {
        'user_count': user_count,
        'active_users': active_users,
        'top_referrers': top_referrers,
        'badge_counts': badge_counts,
        'level_dist': level_dist,
    })

@staff_member_required
def admin_bot_analytics(request):
    # Aggregate download counts for each .ex5 file
    bot_stats = (
        AuditLog.objects.filter(action='ea_download', object_type='EAFile')
        .values('object_id')
        .annotate(count=Count('id'))
        .order_by('-count')
    )
    bot_stats = [{'name': b['object_id'], 'count': b['count']} for b in bot_stats]
    return render(request, 'admin_bot_analytics.html', {'bot_stats': bot_stats})

@login_required
def complete_onboarding(request):
    profile = get_or_create_userprofile(request.user)
    profile.onboarding_complete = True
    profile.save()
    return redirect('dashboard')

@login_required
def progress_dashboard(request):
    ul = get_or_create_userlevel(request.user)
    badges = UserBadge.objects.filter(user=request.user).select_related('badge')
    events = AnalyticsEvent.objects.filter(user=request.user).order_by('-created_at')[:30]
    return render(request, 'progress_dashboard.html', {
        'userlevel': ul,
        'badges': badges,
        'events': events,
    })

# Leaderboard view
def leaderboard(request):
    # Top referrers
    top_referrers = Referral.objects.values('referrer__username').annotate(total=Count('referred_user')).order_by('-total')[:10]
    return render(request, 'leaderboard.html', {'top_referrers': top_referrers})

@csrf_exempt
@login_required
def api_social_share(request):
    if request.method == 'POST':
        # Only award once per day
        from django.utils.timezone import now as tz_now
        today = tz_now().date()
        shared_today = SocialShareEvent.objects.filter(user=request.user, shared_at__date=today).exists()
        if not shared_today:
            SocialShareEvent.objects.create(user=request.user)
            add_xp(request.user, 10, reason="social_share")
            award_badge(request.user, "Social Sharer")
            AnalyticsEvent.objects.create(user=request.user, event_type="social_share")
        return JsonResponse({'status':'ok'})
    return JsonResponse({'status':'error'}, status=405)

@login_required
def api_token_view(request):
    token, created = Token.objects.get_or_create(user=request.user)
    if request.method == 'POST':
        if 'revoke' in request.GET:
            token.delete()
            token = None
            message = 'Token revoked!'
        else:
            token.delete()
            token = Token.objects.create(user=request.user)
            message = 'Token regenerated!'
    else:
        message = None
    return render(request, 'api_token.html', {'token': token.key if token else None, 'message': message})

@login_required
@require_http_methods(["GET", "POST"])
def support_ticket_view(request):
    submitted = False
    if request.method == 'POST':
        subject = request.POST.get('subject', '').strip()
        message = request.POST.get('message', '').strip()
        if subject and message:
            SupportTicket.objects.create(user=request.user, subject=subject, message=message)
            submitted = True
    return render(request, 'support_ticket.html', {'submitted': submitted})

@login_required
def forum_home(request):
    categories = ForumCategory.objects.all()
    return render(request, 'forum_home.html', {'categories': categories})

@login_required
def forum_category(request, category_id):
    category = ForumCategory.objects.get(id=category_id)
    topics = category.topics.select_related('user').order_by('-created_at')
    return render(request, 'forum_category.html', {'category': category, 'topics': topics})

@login_required
def forum_topic(request, topic_id):
    topic = ForumTopic.objects.select_related('category', 'user').get(id=topic_id)
    posts = topic.posts.select_related('user').order_by('created_at')
    if request.method == 'POST':
        message = request.POST.get('message', '').strip()
        if message:
            ForumPost.objects.create(topic=topic, user=request.user, message=message)
    posts = topic.posts.select_related('user').order_by('created_at')
    return render(request, 'forum_topic.html', {'topic': topic, 'posts': posts})

@login_required
def forum_new_topic(request):
    categories = ForumCategory.objects.all()
    selected_category = request.GET.get('category')
    if request.method == 'POST':
        category_id = request.POST.get('category')
        title = request.POST.get('title', '').strip()
        message = request.POST.get('message', '').strip()
        if category_id and title and message:
            category = ForumCategory.objects.get(id=category_id)
            topic = ForumTopic.objects.create(category=category, user=request.user, title=title)
            ForumPost.objects.create(topic=topic, user=request.user, message=message)
            return redirect(f'/forum/topic/{topic.id}/')
    return render(request, 'forum_new_topic.html', {'categories': categories, 'selected_category': selected_category})

from .models import Notification
from django.http import JsonResponse

@login_required
def notifications_list(request):
    notifications = Notification.objects.filter(user=request.user).order_by('-created_at')[:20]
    data = [
        {
            'id': n.id,
            'type': n.type,
            'message': n.message,
            'url': n.url,
            'is_read': n.is_read,
            'created_at': n.created_at.strftime('%Y-%m-%d %H:%M')
        } for n in notifications
    ]
    unread_count = Notification.objects.filter(user=request.user, is_read=False).count()
    return JsonResponse({'notifications': data, 'unread_count': unread_count})

@login_required
def mark_notification_read(request, notification_id):
    Notification.objects.filter(id=notification_id, user=request.user).update(is_read=True)
    return JsonResponse({'success': True})

@login_required
def request_license(request, ea_id):
    from .models import ExpertAdvisor, LicenseKey, Subscription
    ea = ExpertAdvisor.objects.get(id=ea_id)
    subscriptions = Subscription.objects.filter(user=request.user, is_active=True, plan__in=ea.plans.all())
    if not subscriptions.exists():
        return redirect('dashboard')
    # Check if license already exists
    if not LicenseKey.objects.filter(user=request.user, ea=ea).exists():
        license_obj = LicenseKey.objects.create(user=request.user, ea=ea, plan=subscriptions.first().plan)
        AuditLog.objects.create(user=request.user, action='license_request', object_type='LicenseKey', object_id=str(license_obj.id), extra_data={'ea': ea.name})
    return redirect('dashboard')

@login_required
def revoke_license(request, license_id):
    from .models import LicenseKey
    lic = LicenseKey.objects.get(id=license_id, user=request.user)
    lic.status = 'revoked'
    lic.deactivated_at = timezone.now()
    lic.save()
    AuditLog.objects.create(user=request.user, action='license_revoke', object_type='LicenseKey', object_id=str(lic.id), extra_data={'ea': lic.ea.name})
    return redirect('dashboard')

from django.views.decorators.http import require_POST
from django.shortcuts import get_object_or_404
from django.core.mail import send_mail
from django.conf import settings

@login_required
@require_POST
def cancel_subscription(request, sub_id):
    sub = get_object_or_404(Subscription, id=sub_id, user=request.user, is_active=True)
    sub.is_active = False
    sub.end_date = timezone.now()
    sub.save()
    # Notify user
    send_mail(
        subject='Subscription Cancelled',
        message=f'Dear {request.user.username}, your subscription to {sub.plan.name} has been cancelled.',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[request.user.email],
        fail_silently=True,
    )
    return redirect('dashboard')

@login_required
@require_POST
def renew_subscription(request, sub_id):
    sub = get_object_or_404(Subscription, id=sub_id, user=request.user)
    if not sub.is_active:
        sub.is_active = True
        sub.start_date = timezone.now()
        sub.end_date = timezone.now() + timezone.timedelta(days=30)  # Default 1 month renewal
        sub.save()
        send_mail(
            subject='Subscription Renewed',
            message=f'Dear {request.user.username}, your subscription to {sub.plan.name} has been renewed.',
            from_email=settings.DEFAULT_FROM_EMAIL,
            recipient_list=[request.user.email],
            fail_silently=True,
        )
    return redirect('dashboard')

@login_required
@require_POST
def request_plan_change(request):
    plan_id = request.POST.get('plan_id')
    if not plan_id:
        return redirect('dashboard')
    from .models import SubscriptionPlan
    plan = get_object_or_404(SubscriptionPlan, id=plan_id)
    # Notify admin (or handle automatically if desired)
    from django.core.mail import send_mail
    from django.conf import settings
    send_mail(
        subject='Plan Change Request',
        message=f'User {request.user.username} ({request.user.email}) requested to change to plan: {plan.name}',
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[settings.DEFAULT_FROM_EMAIL],
        fail_silently=True,
    )
    # Optionally, log the request or provide user feedback
    return redirect('dashboard')

from django.conf import settings
import os
from django.http import FileResponse, Http404
from .models import AuditLog

@login_required
def bots_portal(request):
    from .models import ExpertAdvisor, EAFile
    # Show all ExpertAdvisors and their EAFile(s)
    bots = ExpertAdvisor.objects.prefetch_related('files').all().order_by('name')
    return render(request, 'bots.html', {'bots': bots})

@login_required
def download_bot(request, file_id):
    try:
        from .models import EAFile
        ea_file = EAFile.objects.select_related('ea').get(id=file_id)
        # Access control: restrict premium bots
        if ea_file.ea.is_premium:
            # Check if user has active paid subscription
            has_access = request.user.subscription_set.filter(is_active=True, plan__price__gt=0).exists()
            if not has_access and not request.user.is_staff:
                from django.contrib import messages
                messages.error(request, "This bot is restricted to premium users. Please upgrade your subscription.")
                from django.shortcuts import redirect
                return redirect('bots_portal')
        # Log the download event for analytics
        AuditLog.objects.create(
            user=request.user,
            action='ea_download',
            object_type='EAFile',
            object_id=str(ea_file.id),
            extra_data={'ip': request.META.get('REMOTE_ADDR'), 'ea': ea_file.ea.name, 'version': ea_file.version}
        )
        return FileResponse(ea_file.file.open('rb'), as_attachment=True, filename=ea_file.file.name.split('/')[-1])
    except EAFile.DoesNotExist:
        raise Http404('Bot file not found')

def home(request):
    return render(request, 'home.html')

def payment_cancelled(request):
    return render(request, 'payment_cancelled.html')

def get_user_referral(user):
    # Returns the Referral object where this user is the referred user, or None
    try:
        return Referral.objects.get(referred_user=user)
    except Referral.DoesNotExist:
        return None

def get_referred_count(user):
    # Returns the number of users this user has referred
    return Referral.objects.filter(referrer=user, referred_user__isnull=False).count()

from django.contrib.auth.views import LogoutView
from django.views.decorators.http import require_http_methods
from django.utils.decorators import method_decorator

@method_decorator(require_http_methods(["POST"]), name='dispatch')
class SecureLogoutView(LogoutView):
    next_page = '/'
