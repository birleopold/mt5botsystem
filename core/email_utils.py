from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from django.utils.html import strip_tags
from django.conf import settings
from django.contrib.sites.shortcuts import get_current_site
from django.urls import reverse


def send_html_email(subject, template_name, context, to_email, from_email=None):
    """
    Sends an HTML email with a text alternative part
    
    Args:
        subject: Email subject
        template_name: Path to HTML email template
        context: Context dictionary for template rendering
        to_email: Recipient email address (string or list)
        from_email: Sender email (if None, uses DEFAULT_FROM_EMAIL setting)
    """
    # If there's no logo URL in context, add the default one
    if 'logo_url' not in context:
        # Generate an absolute URL for the logo
        protocol = 'https' if settings.SECURE_SSL_REDIRECT else 'http'
        domain = settings.ALLOWED_HOSTS[0] if settings.ALLOWED_HOSTS else 'localhost:8000'
        logo_url = f"{protocol}://{domain}{settings.STATIC_URL}img/logo.png"
        context['logo_url'] = logo_url
        
    # Add support URL if not present
    if 'support_url' not in context:
        context['support_url'] = f"{protocol}://{domain}{reverse('support')}"
        
    # Add unsubscribe URL if not present and user is in context
    if 'unsubscribe_url' not in context and 'user' in context:
        context['unsubscribe_url'] = f"{protocol}://{domain}{reverse('email_preferences')}"
    
    # Render HTML content
    html_content = render_to_string(template_name, context)
    
    # Create plain text version by stripping HTML
    text_content = strip_tags(html_content)
    
    # Create email message
    from_email = from_email or settings.DEFAULT_FROM_EMAIL
    email = EmailMultiAlternatives(
        subject=subject,
        body=text_content,
        from_email=from_email,
        to=[to_email] if isinstance(to_email, str) else to_email
    )
    
    # Attach HTML content
    email.attach_alternative(html_content, "text/html")
    
    # Send email
    email.send()
    
    return True
