"""
URL configuration for mt5saas project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from rest_framework import permissions
from drf_yasg.views import get_schema_view
from drf_yasg import openapi
from rest_framework import routers
from core import api_views
from django.conf import settings
from django.conf.urls.static import static

# Register API endpoints with a router for drf-yasg autodiscovery
router = routers.DefaultRouter()
# Example: router.register(r'payments', api_views.PaymentHistoryView, basename='payment')
# Note: Only ViewSets can be registered, but your endpoints are APIView subclasses.

schema_view = get_schema_view(
   openapi.Info(
      title="TheAutomata API",
      default_version='v1',
      description=""" 
      Welcome to the TheAutomata API documentation.
      
      **Authentication:**
      - All endpoints require authentication via Token.
      - Obtain your token by logging in and using the `/api-token/` endpoint.
      - Add your token to the `Authorization` header as: `Token <your_token>`
      
      For support, contact: support@yourdomain.com
      """,
      contact=openapi.Contact(email="support@yourdomain.com", name="TheAutomata Support"),
      license=openapi.License(name="MIT License", url="https://opensource.org/licenses/MIT"),
      terms_of_service="https://yourdomain.com/terms/",
   ),
   public=False,
   permission_classes=(permissions.IsAuthenticated,),
)

urlpatterns = [
    path('admin/', admin.site.urls),  # Django's built-in admin site
    path('', include('core.urls')),  # Include app URLs at the root
    path('docs/', schema_view.with_ui('swagger', cache_timeout=0), name='schema-swagger-ui'),
    path('redoc/', schema_view.with_ui('redoc', cache_timeout=0), name='schema-redoc'),
    path('swagger.json', schema_view.without_ui(cache_timeout=0), name='schema-json'),
    path('swagger.yaml', schema_view.without_ui(cache_timeout=0), name='schema-yaml'),
    # Optionally expose DRF router endpoints for autodiscovery
    path('api/', include(router.urls)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
