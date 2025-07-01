from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, permissions
from rest_framework.authtoken.models import Token
from django.shortcuts import get_object_or_404
from .models import LicenseKey, ExpertAdvisor
from .serializers import LicenseKeyValidateSerializer, LicenseKeyActionSerializer, LicenseKeyStatusSerializer
from django.utils import timezone
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.contrib.auth import authenticate
from core.models import LicenseKey, Subscription, Payment, ApiKey
from django.utils.decorators import method_decorator
from django.views import View
from rest_framework.throttling import UserRateThrottle
from drf_yasg.utils import swagger_auto_schema
from drf_yasg import openapi

class ApiKeyAuthMixin:
    def get_user_from_apikey(self, request):
        api_key = request.headers.get('X-API-KEY') or request.GET.get('api_key')
        if not api_key:
            return None
        try:
            key_obj = ApiKey.objects.get(key=api_key)
            key_obj.last_used = timezone.now()
            key_obj.save(update_fields=['last_used'])
            return key_obj.user
        except ApiKey.DoesNotExist:
            return None

class ApiKeyRateThrottle(UserRateThrottle):
    scope = 'apikey'
    def get_cache_key(self, request, view):
        api_key = request.headers.get('X-API-KEY') or request.GET.get('api_key')
        if api_key:
            return self.cache_format % {
                'scope': self.scope,
                'ident': api_key
            }
        return super().get_cache_key(request, view)

class LicenseValidateView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        serializer = LicenseKeyValidateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        key = serializer.validated_data['key']
        ea_id = serializer.validated_data['ea_id']
        lic = get_object_or_404(LicenseKey, key=key, ea_id=ea_id)
        data = LicenseKeyStatusSerializer(lic).data
        data['valid'] = lic.status == 'active'
        return Response(data)

class LicenseActivateView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        serializer = LicenseKeyActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        key = serializer.validated_data['key']
        lic = get_object_or_404(LicenseKey, key=key)
        if lic.status != 'active':
            lic.status = 'active'
            lic.activated_at = timezone.now()
            lic.save()
        return Response({'activated': True, 'key': lic.key})

class LicenseDeactivateView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        serializer = LicenseKeyActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        key = serializer.validated_data['key']
        lic = get_object_or_404(LicenseKey, key=key)
        if lic.status != 'revoked':
            lic.status = 'revoked'
            lic.deactivated_at = timezone.now()
            lic.save()
        return Response({'deactivated': True, 'key': lic.key})

class EAConfigView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    def get(self, request):
        key = request.query_params.get('key')
        if not key:
            return Response({'detail': 'Missing license key.'}, status=400)
        lic = get_object_or_404(LicenseKey, key=key, status='active')
        # Example config, extend as needed
        config = {
            'ea_name': lic.ea.name,
            'plan': lic.plan.name,
            'user': lic.user.username,
            'settings': {
                'max_trades': 5,
                'risk_level': 'medium',
            }
        }
        return Response({'config': config})

    def post(self, request):
        # Usage tracking (optional)
        key = request.data.get('key')
        usage = request.data.get('usage')
        if not key or not usage:
            return Response({'detail': 'Missing key or usage.'}, status=400)
        lic = get_object_or_404(LicenseKey, key=key, status='active')
        # Log or process usage as needed
        # For now, just acknowledge receipt
        return Response({'received': True})

class LicenseListView(APIView, ApiKeyAuthMixin):
    throttle_classes = [ApiKeyRateThrottle]
    def post(self, request):
        user = self.get_user_from_apikey(request)
        if not user:
            username = request.data.get('username')
            password = request.data.get('password')
            user = authenticate(username=username, password=password)
        if not user:
            return Response({'error': 'Invalid credentials or API key'}, status=403)
        licenses = LicenseKey.objects.filter(user=user)
        data = [
            {
                'key': lic.key,
                'ea': lic.ea.name,
                'plan': lic.plan.name,
                'status': lic.status,
                'created_at': lic.created_at,
                'expires_at': lic.expires_at,
            }
            for lic in licenses
        ]
        return Response({'licenses': data})

class SubscriptionStatusView(APIView, ApiKeyAuthMixin):
    throttle_classes = [ApiKeyRateThrottle]
    def post(self, request):
        user = self.get_user_from_apikey(request)
        if not user:
            username = request.data.get('username')
            password = request.data.get('password')
            user = authenticate(username=username, password=password)
        if not user:
            return Response({'error': 'Invalid credentials or API key'}, status=403)
        subs = Subscription.objects.filter(user=user)
        data = [
            {
                'plan': sub.plan.name,
                'is_active': sub.is_active,
                'start_date': sub.start_date,
                'end_date': sub.end_date,
            }
            for sub in subs
        ]
        return Response({'subscriptions': data})

class PaymentHistoryView(APIView, ApiKeyAuthMixin):
    throttle_classes = [ApiKeyRateThrottle]

    @swagger_auto_schema(
        operation_description="""
        Retrieve the payment history for the authenticated user.
        
        **Authentication:**
        - Token or API key required in the Authorization header.
        - Example: `Authorization: Token <your_token>`
        
        **Request Example:**
        ```json
        {
            "username": "user1",
            "password": "your_password"
        }
        ```
        """,
        request_body=openapi.Schema(
            type=openapi.TYPE_OBJECT,
            properties={
                'username': openapi.Schema(type=openapi.TYPE_STRING, description='User username'),
                'password': openapi.Schema(type=openapi.TYPE_STRING, description='User password'),
            },
            required=['username', 'password']
        ),
        responses={
            200: openapi.Response(
                description="List of payment records for the user.",
                examples={
                    "application/json": {
                        "payments": [
                            {
                                "amount": "49.99",
                                "status": "confirmed",
                                "created_at": "2025-04-26T04:00:00Z",
                                "method": "cash",
                                "invoice_url": "https://example.com/invoice/123/"
                            }
                        ]
                    }
                }
            ),
            403: openapi.Response(description="Invalid credentials or API key")
        }
    )
    def post(self, request):
        user = self.get_user_from_apikey(request)
        if not user:
            username = request.data.get('username')
            password = request.data.get('password')
            user = authenticate(username=username, password=password)
        if not user:
            return Response({'error': 'Invalid credentials or API key'}, status=403)
        payments = Payment.objects.filter(user=user)
        data = [
            {
                'amount': pay.amount,
                'status': pay.status,
                'created_at': pay.created_at,
                'method': pay.method,
                'invoice_url': getattr(pay, 'invoice_url', None),
            }
            for pay in payments
        ]
        return Response({'payments': data})
