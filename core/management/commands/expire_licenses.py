from django.core.management.base import BaseCommand
from core.models import LicenseKey
from django.utils import timezone
from django.core.mail import send_mail
from django.conf import settings

class Command(BaseCommand):
    help = 'Deactivate expired licenses and optionally notify users.'

    def handle(self, *args, **kwargs):
        now = timezone.now()
        expired = LicenseKey.objects.filter(expires_at__lte=now, status='active')
        count = expired.count()
        for lic in expired:
            lic.status = 'revoked'
            lic.deactivated_at = now
            lic.save()
            # Send email notification to user
            send_mail(
                subject='Your License Has Expired',
                message=f'Dear {lic.user.username}, your license for {lic.ea.name} has expired and is now deactivated.',
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[lic.user.email],
                fail_silently=True,
            )
        self.stdout.write(self.style.SUCCESS(f"{count} licenses expired and deactivated. Users notified."))
