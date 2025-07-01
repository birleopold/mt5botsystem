from django import template

register = template.Library()

@register.filter
def resource_icon(resource_type):
    """Return the appropriate Font Awesome icon class for a resource type"""
    icons = {
        'article': 'fa-file-alt',
        'video': 'fa-video',
        'pdf': 'fa-file-pdf',
        'course': 'fa-graduation-cap',
        'webinar': 'fa-laptop',
    }
    return icons.get(resource_type, 'fa-file')

@register.filter
def resource_color(resource_type):
    """Return the appropriate Bootstrap color class for a resource type"""
    colors = {
        'article': 'primary',
        'video': 'danger',
        'pdf': 'success',
        'course': 'warning',
        'webinar': 'info',
    }
    return colors.get(resource_type, 'secondary')

@register.filter
def get_item(dictionary, key):
    """Get an item from a dictionary using the key"""
    return dictionary.get(key, 0)
