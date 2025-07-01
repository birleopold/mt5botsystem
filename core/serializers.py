from rest_framework import serializers
from .models import LicenseKey

class LicenseKeyValidateSerializer(serializers.Serializer):
    key = serializers.CharField()
    ea_id = serializers.IntegerField()

class LicenseKeyActionSerializer(serializers.Serializer):
    key = serializers.CharField()

class LicenseKeyStatusSerializer(serializers.ModelSerializer):
    class Meta:
        model = LicenseKey
        fields = ['key', 'user', 'ea', 'plan', 'status', 'created_at', 'activated_at', 'deactivated_at']
