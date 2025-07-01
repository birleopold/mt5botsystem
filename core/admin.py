from django.contrib import admin
from django.urls import path
from core.admin_dashboard_extra import admin_dashboard_extra
from .models import SubscriptionPlan, Subscription, Payment, Referral, ReferralReward, Ticket, ReferralConfig, Notification, UserProfile, Badge, UserBadge, AnalyticsEvent, UserLevel, ExpertAdvisor, EAFile, LicenseKey, SupportTicket, ForumCategory, ForumTopic, ForumPost, ForumBadge, UserForumBadge, AuditLog, ApiKey
from .admin_learning import LearningCategoryAdmin, LearningResourceAdmin, UserProgressAdmin
from .models_learning import LearningCategory, LearningResource, UserProgress
from .views import activate_subscription
from django.core.mail import send_mail
from django.conf import settings
from django.contrib.auth.models import User, Group
from rest_framework.authtoken.models import Token
from django.contrib.auth.admin import UserAdmin, GroupAdmin
from rest_framework.authtoken.admin import TokenAdmin

# Register your models here.

class CustomAdminSite(admin.AdminSite):
    site_header = "TheAutomata Admin"
    site_title = "TheAutomata Admin Portal"
    index_title = "Welcome to the TheAutomata Admin Portal"

    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path('dashboard/extra/', self.admin_view(admin_dashboard_extra), name='admin-dashboard-extra'),
        ]
        return custom_urls + urls

admin.site = CustomAdminSite()

admin.site.register(SubscriptionPlan)

# --- Subscription admin best practices: show is_active, allow quick filtering, display user and plan ---
class SubscriptionAdmin(admin.ModelAdmin):
    list_display = ('user', 'plan', 'is_active', 'start_date', 'end_date')
    list_filter = ('is_active', 'plan')
    search_fields = ('user__username',)
    readonly_fields = ('start_date', 'end_date')

admin.site.unregister(Subscription) if admin.site.is_registered(Subscription) else None
admin.site.register(Subscription, SubscriptionAdmin)

# --- Payment admin best practices: show payment status, allow quick approval, filter by status ---
class PaymentAdmin(admin.ModelAdmin):
    list_display = ('user', 'plan', 'amount', 'method', 'status', 'created_at')
    list_filter = ('status', 'method', 'plan')
    actions = ['mark_as_confirmed']

    def mark_as_confirmed(self, request, queryset):
        updated = queryset.update(status='confirmed')
        for payment in queryset:
            # Send user notification
            send_mail(
                subject='Payment Confirmed',
                message=f'Dear {payment.user.username}, your payment for plan {payment.plan.name} has been confirmed. Your subscription is now active.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[payment.user.email],
                fail_silently=True,
            )
            # Send admin notification (optional)
            send_mail(
                subject='Payment Confirmed (Admin Copy)',
                message=f'Payment for user {payment.user.username} and plan {payment.plan.name} has been confirmed.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[settings.DEFAULT_FROM_EMAIL],
                fail_silently=True,
            )
        self.message_user(request, f"{updated} payment(s) marked as confirmed and notifications sent.")
    mark_as_confirmed.short_description = "Mark selected payments as confirmed"

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        # Activate subscription and send emails if confirmed and not already activated
        if obj.status == 'confirmed':
            activate_subscription(obj.user, obj.plan, obj)

admin.site.unregister(Payment) if admin.site.is_registered(Payment) else None
admin.site.register(Payment, PaymentAdmin)

# Register all models with the custom admin site
admin.site.register(Referral, admin.ModelAdmin)
admin.site.register(ReferralReward, admin.ModelAdmin)
admin.site.register(ReferralConfig, admin.ModelAdmin)
admin.site.register(Ticket, admin.ModelAdmin)
admin.site.register(Notification, admin.ModelAdmin)
admin.site.register(UserProfile, admin.ModelAdmin)
admin.site.register(Badge, admin.ModelAdmin)
admin.site.register(UserBadge, admin.ModelAdmin)
admin.site.register(AnalyticsEvent, admin.ModelAdmin)
admin.site.register(UserLevel, admin.ModelAdmin)
admin.site.register(ExpertAdvisor, admin.ModelAdmin)
admin.site.register(EAFile, admin.ModelAdmin)
admin.site.register(LicenseKey, admin.ModelAdmin)
admin.site.register(SupportTicket, admin.ModelAdmin)
admin.site.register(ForumCategory, admin.ModelAdmin)
admin.site.register(ForumTopic, admin.ModelAdmin)
admin.site.register(ForumPost, admin.ModelAdmin)
admin.site.register(ForumBadge, admin.ModelAdmin)
admin.site.register(UserForumBadge, admin.ModelAdmin)
admin.site.register(ApiKey, admin.ModelAdmin)

class AuditLogAdmin(admin.ModelAdmin):
    list_display = ('user', 'action', 'object_type', 'object_id', 'timestamp')
    search_fields = ('user__username', 'action', 'object_type', 'object_id')
    list_filter = ('action', 'object_type', 'timestamp')
    readonly_fields = ('user', 'action', 'object_type', 'object_id', 'timestamp', 'extra_data')

admin.site.register(AuditLog, AuditLogAdmin)

# Register Learning Center models
admin.site.register(LearningCategory, LearningCategoryAdmin)
admin.site.register(LearningResource, LearningResourceAdmin)
admin.site.register(UserProgress, UserProgressAdmin)

# Unregister built-ins if already registered (avoids duplicate admin errors)
if admin.site.is_registered(User):
    admin.site.unregister(User)
if admin.site.is_registered(Group):
    admin.site.unregister(Group)
if admin.site.is_registered(Token):
    admin.site.unregister(Token)
admin.site.register(User, UserAdmin)
admin.site.register(Group, GroupAdmin)
admin.site.register(Token, TokenAdmin)
