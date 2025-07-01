from django.db import models
from django.contrib.auth.models import User
from django.conf import settings
from django.utils import timezone
from django.contrib.auth import get_user_model
import uuid
import json
import secrets

# Create your models here.

class SubscriptionPlan(models.Model):
    name = models.CharField(max_length=50, unique=True)
    description = models.TextField(blank=True)
    price = models.DecimalField(max_digits=8, decimal_places=2)
    is_active = models.BooleanField(default=True)
    # Add more fields as needed (e.g., allowed_eas, max_bots, etc.)

    def __str__(self):
        return self.name

class Subscription(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    plan = models.ForeignKey(SubscriptionPlan, on_delete=models.CASCADE)
    start_date = models.DateTimeField(auto_now_add=True)
    end_date = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    stripe_subscription_id = models.CharField(max_length=100, blank=True, null=True)

    def __str__(self):
        return f"{self.user.username} - {self.plan.name}"

class Payment(models.Model):
    PAYMENT_METHODS = [
        ('cash', 'Cash'),
    ]
    PAYMENT_STATUS = [
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('failed', 'Failed'),
    ]
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    plan = models.ForeignKey(SubscriptionPlan, on_delete=models.CASCADE)
    amount = models.DecimalField(max_digits=8, decimal_places=2)
    method = models.CharField(max_length=20, choices=PAYMENT_METHODS, default='cash')
    status = models.CharField(max_length=20, choices=PAYMENT_STATUS, default='pending')
    transaction_id = models.CharField(max_length=100, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    proof_of_payment = models.FileField(upload_to='payment_proofs/', blank=True, null=True)
    notes = models.TextField(blank=True)

    def __str__(self):
        return f"{self.user.username} - {self.plan.name} - {self.method} - {self.status}"

class Referral(models.Model):
    referrer = models.ForeignKey(get_user_model(), on_delete=models.CASCADE, related_name='referrals_made')
    code = models.CharField(max_length=32, unique=True)
    referred_user = models.OneToOneField(get_user_model(), on_delete=models.CASCADE, null=True, blank=True, related_name='referral_used')
    created_at = models.DateTimeField(auto_now_add=True)
    reward_granted = models.BooleanField(default=False)
    def __str__(self):
        return f"{self.referrer.username} - {self.code}"

class ReferralConfig(models.Model):
    reward_threshold = models.PositiveIntegerField(default=3, help_text="Number of successful referrals needed for a reward.")
    reward_type = models.CharField(max_length=32, choices=[('free_month', 'Free Month'), ('discount', 'Discount'), ('other', 'Other')], default='free_month')
    reward_value = models.CharField(max_length=64, blank=True, help_text="E.g. 1 for one free month, or 10% for discount.")
    active = models.BooleanField(default=True)
    def __str__(self):
        return f"{self.reward_threshold} referrals: {self.reward_type} ({self.reward_value})"

class ReferralReward(models.Model):
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    referral = models.ForeignKey(Referral, on_delete=models.CASCADE)
    reward_type = models.CharField(max_length=32, choices=[('free_month', 'Free Month'), ('discount', 'Discount'), ('other', 'Other')])
    reward_value = models.CharField(max_length=64, blank=True)
    granted_at = models.DateTimeField(default=timezone.now)
    def __str__(self):
        return f"{self.user.username} - {self.reward_type}"

class Notification(models.Model):
    NOTIFICATION_TYPES = [
        ('forum_reply', 'Forum Reply'),
        ('badge', 'Badge Awarded'),
        ('support', 'Support Update'),
        ('admin', 'Admin Message'),
    ]
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE, related_name='notifications')
    type = models.CharField(max_length=24, choices=NOTIFICATION_TYPES)
    message = models.TextField()
    url = models.CharField(max_length=256, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.user.username}: {self.type} - {self.message[:40]}"

class Ticket(models.Model):
    STATUS_CHOICES = [
        ('open', 'Open'),
        ('pending', 'Pending'),
        ('closed', 'Closed'),
    ]
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    subject = models.CharField(max_length=128)
    message = models.TextField()
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default='open')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    admin_response = models.TextField(blank=True)
    def __str__(self):
        return f"{self.user.username} - {self.subject} ({self.status})"

class UserProfile(models.Model):
    user = models.OneToOneField(get_user_model(), on_delete=models.CASCADE)
    onboarding_complete = models.BooleanField(default=False)
    first_login = models.DateTimeField(null=True, blank=True)
    def __str__(self):
        return self.user.username

class Badge(models.Model):
    name = models.CharField(max_length=64)
    description = models.CharField(max_length=255)
    icon = models.CharField(max_length=128, blank=True, help_text="FontAwesome or image class/url")
    def __str__(self):
        return self.name

class UserBadge(models.Model):
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    badge = models.ForeignKey(Badge, on_delete=models.CASCADE)
    awarded_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.user.username}: {self.badge.name}"

class UserLevel(models.Model):
    user = models.OneToOneField(get_user_model(), on_delete=models.CASCADE)
    level = models.PositiveIntegerField(default=1)
    xp = models.PositiveIntegerField(default=0)
    last_activity = models.DateTimeField(null=True, blank=True)
    streak = models.PositiveIntegerField(default=0)
    def __str__(self):
        return f"{self.user.username}: Level {self.level} (XP: {self.xp})"
    def xp_for_next_level(self):
        return 100 * self.level
    def progress_percent(self):
        return int(100 * self.xp / self.xp_for_next_level())

class AnalyticsEvent(models.Model):
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE, null=True, blank=True)
    event_type = models.CharField(max_length=64)
    event_value = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.user}: {self.event_type} at {self.created_at}" if self.user else f"Anon: {self.event_type} at {self.created_at}"

class SocialShareEvent(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    platform = models.CharField(max_length=20)
    referral_url = models.URLField()
    message = models.TextField(blank=True)
    shared_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.username} shared on {self.platform} at {self.shared_at}"

class ShareReward(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    event = models.ForeignKey('SocialShareEvent', on_delete=models.CASCADE)
    reward_type = models.CharField(max_length=32)
    reward_value = models.IntegerField(default=1)
    rewarded_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.user.username} rewarded for share {self.event_id} ({self.reward_type})"

class ExpertAdvisor(models.Model):
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    plans = models.ManyToManyField('SubscriptionPlan', blank=True)
    is_premium = models.BooleanField(default=False, help_text="Restrict download to premium users only")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    def __str__(self):
        return self.name

class EAFile(models.Model):
    ea = models.ForeignKey(ExpertAdvisor, on_delete=models.CASCADE, related_name='files')
    file = models.FileField(upload_to='ea_files/')
    version = models.CharField(max_length=32)
    changelog = models.TextField(blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.ea.name} v{self.version}"

class LicenseKey(models.Model):
    key = models.CharField(max_length=64, unique=True, default=uuid.uuid4)
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    ea = models.ForeignKey(ExpertAdvisor, on_delete=models.CASCADE)
    plan = models.ForeignKey('SubscriptionPlan', on_delete=models.CASCADE)
    status = models.CharField(max_length=16, choices=[('active','Active'),('revoked','Revoked')], default='active')
    created_at = models.DateTimeField(auto_now_add=True)
    activated_at = models.DateTimeField(null=True, blank=True)
    deactivated_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    def __str__(self):
        return f"{self.key} - {self.user.username} - {self.ea.name} - {self.status}"
    @property
    def is_expired(self):
        return self.expires_at and self.expires_at <= timezone.now()
    @staticmethod
    def generate(user, ea, plan):
        key = str(uuid.uuid4())
        return LicenseKey.objects.create(user=user, ea=ea, plan=plan, key=key)

class AuditLog(models.Model):
    ACTION_CHOICES = [
        ('license_request', 'License Requested'),
        ('license_revoke', 'License Revoked'),
        ('ea_download', 'EA Downloaded'),
        ('admin_change', 'Admin Change'),
        ('user_login', 'User Login'),
        # Add more as needed
    ]
    user = models.ForeignKey(get_user_model(), on_delete=models.SET_NULL, null=True, blank=True)
    action = models.CharField(max_length=32, choices=ACTION_CHOICES)
    object_type = models.CharField(max_length=64)
    object_id = models.CharField(max_length=64)
    timestamp = models.DateTimeField(auto_now_add=True)
    extra_data = models.JSONField(blank=True, null=True)
    def __str__(self):
        return f"{self.user} {self.action} {self.object_type} {self.object_id} @{self.timestamp}"

class SupportTicket(models.Model):
    STATUS_CHOICES = [
        ('open', 'Open'),
        ('closed', 'Closed'),
        ('pending', 'Pending'),
    ]
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    subject = models.CharField(max_length=200)
    message = models.TextField()
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='open')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    def __str__(self):
        return f"{self.subject} ({self.user.username})"

class ForumCategory(models.Model):
    name = models.CharField(max_length=80)
    description = models.TextField(blank=True)
    def __str__(self):
        return self.name

class ForumTopic(models.Model):
    category = models.ForeignKey(ForumCategory, on_delete=models.CASCADE, related_name='topics')
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    title = models.CharField(max_length=200)
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return self.title

class ForumPost(models.Model):
    topic = models.ForeignKey(ForumTopic, on_delete=models.CASCADE, related_name='posts')
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.user.username}: {self.message[:40]}..." if len(self.message) > 40 else self.message

class ForumBadge(models.Model):
    name = models.CharField(max_length=64)
    description = models.TextField(blank=True)
    icon = models.CharField(max_length=64, blank=True)  # FontAwesome or emoji
    def __str__(self):
        return self.name

class UserForumBadge(models.Model):
    user = models.ForeignKey(get_user_model(), on_delete=models.CASCADE)
    badge = models.ForeignKey(ForumBadge, on_delete=models.CASCADE)
    awarded_at = models.DateTimeField(auto_now_add=True)
    def __str__(self):
        return f"{self.user.username} - {self.badge.name}"

class ApiKey(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    key = models.CharField(max_length=40, unique=True, default=secrets.token_urlsafe)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"API Key for {self.user.username}"
