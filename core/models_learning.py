from django.db import models
from django.utils.text import slugify
from django.urls import reverse
from django.conf import settings

class LearningCategory(models.Model):
    """Categories for learning materials (e.g., Beginner, Advanced, Technical Analysis)"""
    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=120, unique=True)
    description = models.TextField(blank=True)
    icon = models.CharField(max_length=50, help_text="Font Awesome icon class, e.g., 'fa-chart-line'")
    order = models.PositiveIntegerField(default=0, help_text="Display order")
    
    class Meta:
        verbose_name_plural = "Learning Categories"
        ordering = ['order', 'name']
    
    def __str__(self):
        return self.name
    
    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.name)
        super().save(*args, **kwargs)

class LearningResource(models.Model):
    """Learning resources like articles, videos, PDFs, etc."""
    RESOURCE_TYPES = (
        ('article', 'Article'),
        ('video', 'Video'),
        ('pdf', 'PDF Document'),
        ('course', 'Interactive Course'),
        ('webinar', 'Webinar Recording'),
    )
    
    ACCESS_LEVELS = (
        ('free', 'Free'),
        ('basic', 'Basic Plan'),
        ('premium', 'Premium Plan'),
        ('pro', 'Pro Plan'),
    )
    
    title = models.CharField(max_length=200)
    slug = models.SlugField(max_length=220, unique=True)
    category = models.ForeignKey(LearningCategory, on_delete=models.CASCADE, related_name='resources')
    description = models.TextField()
    content = models.TextField(blank=True, help_text="HTML content for articles")
    resource_type = models.CharField(max_length=20, choices=RESOURCE_TYPES)
    access_level = models.CharField(max_length=20, choices=ACCESS_LEVELS, default='free')
    
    # For uploaded files (PDFs, etc.)
    file = models.FileField(upload_to='learning_resources/', blank=True, null=True)
    
    # For videos (embed URLs)
    video_url = models.URLField(blank=True, null=True, help_text="YouTube or Vimeo embed URL")
    
    # For tracking and sorting
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    featured = models.BooleanField(default=False)
    view_count = models.PositiveIntegerField(default=0)
    estimated_duration = models.PositiveIntegerField(
        help_text="Estimated time to complete in minutes", 
        default=0
    )
    
    class Meta:
        ordering = ['-featured', '-created_at']
    
    def __str__(self):
        return self.title
    
    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.title)
        super().save(*args, **kwargs)
    
    def get_absolute_url(self):
        return reverse('learning_resource_detail', args=[self.slug])
    
    def is_accessible_by(self, user):
        """Check if the user has access to this resource based on their subscription"""
        if not user.is_authenticated:
            return self.access_level == 'free'
        
        if user.is_staff:
            return True
        
        # Check if the User model has a subscriptions attribute
        if not hasattr(user, 'subscriptions'):
            return self.access_level == 'free'
            
        # Get the user's active subscription
        active_sub = user.subscriptions.filter(is_active=True).first()
        
        if not active_sub:
            return self.access_level == 'free'
        
        # Check if the subscription has a plan attribute
        if not hasattr(active_sub, 'plan'):
            return self.access_level == 'free'
            
        # Check access based on plan level
        plan_level = active_sub.plan.name.lower()
        
        if 'pro' in plan_level:
            return True  # Pro has access to everything
        elif 'premium' in plan_level:
            return self.access_level in ['free', 'basic', 'premium']
        elif 'basic' in plan_level:
            return self.access_level in ['free', 'basic']
        else:
            return self.access_level == 'free'

class UserProgress(models.Model):
    """Track user progress through learning resources"""
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='learning_progress')
    resource = models.ForeignKey(LearningResource, on_delete=models.CASCADE, related_name='user_progress')
    completed = models.BooleanField(default=False)
    progress_percent = models.PositiveIntegerField(default=0)  # 0-100
    last_accessed = models.DateTimeField(auto_now=True)
    
    class Meta:
        unique_together = ['user', 'resource']
        verbose_name_plural = "User Progress"
    
    def __str__(self):
        return f"{self.user.username} - {self.resource.title} ({self.progress_percent}%)"
