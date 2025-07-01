from django.urls import path, include
from . import views
from django.contrib.auth import views as auth_views
from django.views.generic import TemplateView
from core import api_views
from core import analytics_views
from core.views_audit import audit_history, download_audit_log
from core.admin_analytics import analytics_dashboard
from core.admin_share_analytics import share_analytics_dashboard
from core.admin_dashboard import admin_dashboard
from core.admin_dashboard_extra import admin_dashboard_extra
from . import views_share
from .views import bots_portal, download_bot, SecureLogoutView
from core.views_notifications import notifications_list
from core.views_analytics import trading_dashboard, trading_metrics_json, trade_details, symbol_performance
from core.views_learning import learning_center, category_detail, resource_detail, update_progress, my_learning, download_resource

urlpatterns = [
    path('', views.home, name='home'),
    path('register/', views.register, name='register'),
    path('dashboard/', views.dashboard, name='dashboard'),
    path('submit-ticket/', views.submit_ticket, name='submit_ticket'),
    path('plans/', views.plan_list, name='plan_list'),
    path('checkout/<int:plan_id>/', views.checkout, name='checkout'),
    path('payment/<int:payment_id>/', views.payment_status, name='payment_status'),
    path('manual-payment/<int:plan_id>/', views.manual_payment, name='manual_payment'),
    path('payment-success/', views.payment_status, name='payment_success'),
    path('payment-cancelled/', views.payment_cancelled, name='payment_cancelled'),
    path('login/', auth_views.LoginView.as_view(template_name='registration/login.html'), name='login'),
    path('logout/', SecureLogoutView.as_view(), name='logout'),
    path('password-reset/', auth_views.PasswordResetView.as_view(template_name='registration/password_reset_form.html'), name='password_reset'),
    path('password-reset/done/', auth_views.PasswordResetDoneView.as_view(template_name='registration/password_reset_done.html'), name='password_reset_done'),
    path('reset/<uidb64>/<token>/', auth_views.PasswordResetConfirmView.as_view(template_name='registration/password_reset_confirm.html'), name='password_reset_confirm'),
    path('reset/done/', auth_views.PasswordResetCompleteView.as_view(template_name='registration/password_reset_complete.html'), name='password_reset_complete'),
    # path('webhook/stripe/', views.stripe_webhook, name='stripe_webhook'),
    path('webhook/coinbase/', views.coinbase_webhook, name='coinbase_webhook'),
    # path('binance-payment/<int:payment_id>/', views.binance_payment_instructions, name='binance_payment_instructions'),
    path('privacy/', TemplateView.as_view(template_name='privacy.html'), name='privacy'),
    path('terms/', TemplateView.as_view(template_name='terms.html'), name='terms'),
    path('refund/', TemplateView.as_view(template_name='refund.html'), name='refund'),
    path('contact/', views.contact, name='contact'),
    path('faq/', TemplateView.as_view(template_name='faq.html'), name='faq'),
    path('notifications/', views.notifications, name='notifications'),
    path('notifications/dismiss/<int:note_id>/', views.dismiss_notification, name='dismiss_notification'),
    path('notifications/list/', notifications_list, name='notifications_list'),
    path('leaderboard/', views.leaderboard, name='leaderboard'),
    path('onboarding/complete/', views.complete_onboarding, name='complete_onboarding'),
    path('progress/', views.progress_dashboard, name='progress_dashboard'),
    path('admin-analytics/', views.admin_analytics_summary, name='admin_analytics_summary'),
    path('dashboard-admin/analytics/', analytics_dashboard, name='admin_analytics'),
    path('dashboard-admin/share-analytics/', share_analytics_dashboard, name='admin_share_analytics'),
    path('dashboard-admin/bot-analytics/', views.admin_bot_analytics, name='admin_bot_analytics'),
    path('dashboard-admin/main/', admin_dashboard, name='admin_dashboard'),
    path('extra/', admin_dashboard_extra, name='admin_dashboard_extra'),
    path('analytics/user-data/', analytics_views.user_analytics_data, name='user_analytics_data'),
    path('analytics/admin-data/', analytics_views.admin_analytics_data, name='admin_analytics_data'),
    path('analytics/share-event/', views_share.share_event, name='share_event'),
    path('api/social_share/', views.api_social_share, name='api_social_share'),
    path('api-token/', views.api_token_view, name='api_token'),
    path('api-docs/', TemplateView.as_view(template_name='api_docs.html'), name='api_docs'),
    path('support/', views.support_ticket_view, name='support_ticket'),
    path('forum/', views.forum_home, name='forum_home'),
    path('forum/category/<int:category_id>/', views.forum_category, name='forum_category'),
    path('forum/topic/<int:topic_id>/', views.forum_topic, name='forum_topic'),
    path('forum/new-topic/', views.forum_new_topic, name='forum_new_topic'),
    path('request-license/<int:ea_id>/', views.request_license, name='request_license'),
    path('revoke-license/<int:license_id>/', views.revoke_license, name='revoke_license'),
    path('request-plan-change/', views.request_plan_change, name='request_plan_change'),
    path('audit-history/', audit_history, name='audit_history'),
    path('download-audit-log/', download_audit_log, name='download_audit_log'),
    path('cancel-subscription/<int:sub_id>/', views.cancel_subscription, name='cancel_subscription'),
    path('renew-subscription/<int:sub_id>/', views.renew_subscription, name='renew_subscription'),
    path('bots/', bots_portal, name='bots_portal'),
    path('bots/download/<int:file_id>/', download_bot, name='download_bot'),
]

# Trading Analytics Dashboard URLs
urlpatterns += [
    path('trading/dashboard/', trading_dashboard, name='trading_dashboard'),
    path('trading/metrics/json/', trading_metrics_json, name='trading_metrics_json'),
    path('trading/trades/', trade_details, name='trade_details'),
    path('trading/symbols/', symbol_performance, name='symbol_performance'),
]

# API URLs
urlpatterns += [
    path('api/license/validate/', api_views.LicenseValidateView.as_view(), name='api_license_validate'),
    path('api/license/activate/', api_views.LicenseActivateView.as_view(), name='api_license_activate'),
    path('api/license/deactivate/', api_views.LicenseDeactivateView.as_view(), name='api_license_deactivate'),
    path('api/ea/config/', api_views.EAConfigView.as_view(), name='api_ea_config'),
    path('api/licenses/', api_views.LicenseListView.as_view(), name='api_license_list'),
    path('api/subscriptions/', api_views.SubscriptionStatusView.as_view(), name='api_subscription_status'),
    path('api/payments/', api_views.PaymentHistoryView.as_view(), name='api_payment_history'),
]

# Learning Center URLs
urlpatterns += [
    path('learning/', learning_center, name='learning_center'),
    path('learning/category/<slug:slug>/', category_detail, name='learning_category'),
    path('learning/resource/<slug:slug>/', resource_detail, name='learning_resource_detail'),
    path('learning/my-learning/', my_learning, name='my_learning'),
    path('learning/update-progress/<int:resource_id>/', update_progress, name='update_progress'),
    path('learning/download/<int:resource_id>/', download_resource, name='download_resource'),
]
