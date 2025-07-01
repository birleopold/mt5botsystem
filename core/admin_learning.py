from django.contrib import admin
from django.utils.html import format_html
from .models_learning import LearningCategory, LearningResource, UserProgress

class LearningResourceInline(admin.TabularInline):
    model = LearningResource
    extra = 1
    fields = ('title', 'resource_type', 'access_level', 'featured', 'view_count')
    readonly_fields = ('view_count',)
    show_change_link = True

@admin.register(LearningCategory)
class LearningCategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'resource_count', 'order', 'icon_display')
    search_fields = ('name', 'description')
    prepopulated_fields = {'slug': ('name',)}
    list_editable = ('order',)
    inlines = [LearningResourceInline]
    
    def resource_count(self, obj):
        return obj.resources.count()
    resource_count.short_description = 'Resources'
    
    def icon_display(self, obj):
        return format_html('<i class="fas {}"></i> {}', obj.icon, obj.icon)
    icon_display.short_description = 'Icon'

@admin.register(LearningResource)
class LearningResourceAdmin(admin.ModelAdmin):
    list_display = ('title', 'category', 'resource_type', 'access_level', 'featured', 'view_count', 'created_at')
    list_filter = ('category', 'resource_type', 'access_level', 'featured')
    search_fields = ('title', 'description', 'content')
    prepopulated_fields = {'slug': ('title',)}
    readonly_fields = ('view_count', 'created_at', 'updated_at')
    list_editable = ('featured', 'access_level')
    date_hierarchy = 'created_at'
    fieldsets = (
        (None, {
            'fields': ('title', 'slug', 'category', 'description')
        }),
        ('Content', {
            'fields': ('content', 'resource_type', 'file', 'video_url')
        }),
        ('Settings', {
            'fields': ('access_level', 'featured', 'estimated_duration')
        }),
        ('Statistics', {
            'fields': ('view_count', 'created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def get_queryset(self, request):
        return super().get_queryset(request).select_related('category')

@admin.register(UserProgress)
class UserProgressAdmin(admin.ModelAdmin):
    list_display = ('user', 'resource', 'progress_percent', 'completed', 'last_accessed')
    list_filter = ('completed', 'last_accessed')
    search_fields = ('user__username', 'user__email', 'resource__title')
    readonly_fields = ('last_accessed',)
    list_editable = ('progress_percent', 'completed')
    date_hierarchy = 'last_accessed'
    
    def get_queryset(self, request):
        return super().get_queryset(request).select_related('user', 'resource')
