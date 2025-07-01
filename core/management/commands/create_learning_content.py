from django.core.management.base import BaseCommand
from django.utils.text import slugify
from core.models_learning import LearningCategory, LearningResource
from django.core.files.base import ContentFile
import os
from django.conf import settings

class Command(BaseCommand):
    help = 'Creates sample learning content for the Learning Center'

    def handle(self, *args, **options):
        # Create learning categories
        categories = [
            {
                'name': 'Beginner Trading',
                'description': 'Fundamental concepts and strategies for those new to trading.',
                'icon': 'fa-graduation-cap'
            },
            {
                'name': 'Technical Analysis',
                'description': 'Learn how to analyze charts and identify trading opportunities using technical indicators.',
                'icon': 'fa-chart-line'
            },
            {
                'name': 'Fundamental Analysis',
                'description': 'Understand how economic events and news impact the markets.',
                'icon': 'fa-newspaper'
            },
            {
                'name': 'Trading Psychology',
                'description': 'Master the mental aspects of trading to improve your performance.',
                'icon': 'fa-brain'
            },
            {
                'name': 'MetaTrader 5 Tutorials',
                'description': 'Step-by-step guides to using the MetaTrader 5 platform effectively.',
                'icon': 'fa-desktop'
            },
            {
                'name': 'Expert Advisor Development',
                'description': 'Learn how to create and optimize your own trading robots.',
                'icon': 'fa-robot'
            }
        ]

        created_categories = []
        for i, category_data in enumerate(categories):
            category, created = LearningCategory.objects.get_or_create(
                name=category_data['name'],
                defaults={
                    'description': category_data['description'],
                    'icon': category_data['icon'],
                    'order': i
                }
            )
            created_categories.append(category)
            if created:
                self.stdout.write(self.style.SUCCESS(f'Created category: {category.name}'))
            else:
                self.stdout.write(self.style.WARNING(f'Category already exists: {category.name}'))

        # Create sample resources
        resources = [
            # Beginner Trading Resources
            {
                'title': 'Introduction to Forex Trading',
                'description': 'Learn the basics of forex trading, including key terminology and market structure.',
                'category': 'Beginner Trading',
                'resource_type': 'article',
                'access_level': 'free',
                'content': '<h2>Introduction to Forex Trading</h2><p>The foreign exchange market (Forex, FX, or currency market) is a global decentralized or over-the-counter (OTC) market for the trading of currencies. This market determines foreign exchange rates for every currency. It includes all aspects of buying, selling and exchanging currencies at current or determined prices.</p><h3>Key Concepts</h3><ul><li><strong>Currency Pairs</strong>: Currencies are traded in pairs, such as EUR/USD (Euro/US Dollar).</li><li><strong>Pips</strong>: A pip is the smallest price move that a given exchange rate makes based on market convention.</li><li><strong>Lots</strong>: A lot is a standard unit size of a transaction.</li><li><strong>Leverage</strong>: Leverage allows traders to control larger positions with a relatively small amount of capital.</li></ul><p>This introduction will help you understand the basics before diving deeper into trading strategies and analysis techniques.</p>',
                'estimated_duration': 15,
                'featured': True
            },
            {
                'title': 'Understanding Candlestick Patterns',
                'description': 'Master the art of reading candlestick charts to identify potential market reversals and continuations.',
                'category': 'Technical Analysis',
                'resource_type': 'video',
                'access_level': 'free',
                'video_url': 'https://www.youtube.com/embed/dQw4w9WgXcQ',
                'content': '<h2>Understanding Candlestick Patterns</h2><p>Candlestick charts are a type of financial chart that shows the open, high, low, and close prices for a specific time period. They originated in Japan over 100 years before the West developed the bar and point-and-figure charts.</p><h3>Basic Candlestick Patterns</h3><ul><li><strong>Doji</strong>: Indicates indecision in the market.</li><li><strong>Hammer</strong>: Potential reversal pattern at the bottom of a downtrend.</li><li><strong>Engulfing Pattern</strong>: A two-candle pattern that can signal a reversal.</li><li><strong>Morning Star</strong>: A three-candle pattern indicating a potential bullish reversal.</li></ul><p>Watch the video to see these patterns in action and learn how to identify them on your charts.</p>',
                'estimated_duration': 30,
                'featured': True
            },
            {
                'title': 'Risk Management Fundamentals',
                'description': 'Learn essential risk management techniques to protect your trading capital and ensure long-term success.',
                'category': 'Beginner Trading',
                'resource_type': 'pdf',
                'access_level': 'free',
                'content': '<h2>Risk Management Fundamentals</h2><p>Proper risk management is the cornerstone of successful trading. Without it, even the best trading strategy will eventually fail.</p><h3>Key Risk Management Principles</h3><ul><li><strong>Position Sizing</strong>: Never risk more than 1-2% of your trading capital on a single trade.</li><li><strong>Stop Loss Orders</strong>: Always use stop losses to limit potential losses.</li><li><strong>Risk-Reward Ratio</strong>: Aim for a minimum risk-reward ratio of 1:2 or better.</li><li><strong>Correlation</strong>: Be aware of correlations between different markets to avoid overexposure.</li></ul><p>Download our comprehensive PDF guide to learn more about implementing these principles in your trading.</p>',
                'estimated_duration': 45,
                'featured': True
            },
            {
                'title': 'MetaTrader 5 Platform Overview',
                'description': 'A comprehensive tour of the MetaTrader 5 trading platform, covering navigation, chart setup, and basic functionality.',
                'category': 'MetaTrader 5 Tutorials',
                'resource_type': 'video',
                'access_level': 'free',
                'video_url': 'https://www.youtube.com/embed/dQw4w9WgXcQ',
                'content': '<h2>MetaTrader 5 Platform Overview</h2><p>MetaTrader 5 (MT5) is a powerful trading platform that offers a wide range of features for traders of all levels.</p><h3>Key Features Covered</h3><ul><li><strong>Platform Navigation</strong>: Learn how to navigate the MT5 interface efficiently.</li><li><strong>Chart Setup</strong>: Customize your charts for optimal analysis.</li><li><strong>Order Types</strong>: Understand the different order types available in MT5.</li><li><strong>Technical Indicators</strong>: Access and apply built-in technical indicators.</li></ul><p>Watch this video tutorial to get started with MetaTrader 5 and make the most of its features.</p>',
                'estimated_duration': 25,
                'featured': False
            },
            # Premium Resources
            {
                'title': 'Advanced Price Action Trading Strategies',
                'description': 'Discover sophisticated price action techniques used by professional traders to identify high-probability trading opportunities.',
                'category': 'Technical Analysis',
                'resource_type': 'course',
                'access_level': 'premium',
                'content': '<h2>Advanced Price Action Trading Strategies</h2><p>Price action trading is a methodology that relies on historical prices (open, high, low, and close) to help you make better trading decisions.</p><h3>What You\'ll Learn</h3><ul><li><strong>Support and Resistance Dynamics</strong>: Advanced techniques for identifying key levels.</li><li><strong>Order Flow Analysis</strong>: Understanding how institutional orders affect price movement.</li><li><strong>Multi-Timeframe Analysis</strong>: How to align trades across different timeframes.</li><li><strong>Wyckoff Method</strong>: Applying Wyckoff principles to modern markets.</li></ul><p>This premium course includes 10 video lessons, practical exercises, and a downloadable trading plan template.</p>',
                'estimated_duration': 240,
                'featured': True
            },
            {
                'title': 'Building Your First Expert Advisor',
                'description': 'Step-by-step guide to creating a simple but effective trading robot in MQL5 for MetaTrader 5.',
                'category': 'Expert Advisor Development',
                'resource_type': 'course',
                'access_level': 'premium',
                'content': '<h2>Building Your First Expert Advisor</h2><p>Expert Advisors (EAs) are automated trading programs that can analyze market data and execute trades based on predefined rules.</p><h3>Course Outline</h3><ul><li><strong>MQL5 Basics</strong>: Introduction to the MQL5 programming language.</li><li><strong>EA Structure</strong>: Understanding the components of an Expert Advisor.</li><li><strong>Entry and Exit Logic</strong>: Implementing trading signals in your EA.</li><li><strong>Risk Management</strong>: Adding position sizing and stop loss functionality.</li><li><strong>Optimization</strong>: Testing and optimizing your EA for better performance.</li></ul><p>By the end of this course, you\'ll have created your own functional Expert Advisor ready for testing.</p>',
                'estimated_duration': 180,
                'featured': False
            },
            {
                'title': 'Market Psychology: Mastering Your Emotions',
                'description': 'Learn psychological techniques to overcome fear, greed, and other emotions that can negatively impact your trading decisions.',
                'category': 'Trading Psychology',
                'resource_type': 'webinar',
                'access_level': 'basic',
                'video_url': 'https://www.youtube.com/embed/dQw4w9WgXcQ',
                'content': '<h2>Market Psychology: Mastering Your Emotions</h2><p>Trading psychology is often the difference between consistent profits and frequent losses. This webinar addresses the emotional challenges traders face.</p><h3>Key Topics</h3><ul><li><strong>Fear and Greed Cycle</strong>: Recognizing and breaking destructive emotional patterns.</li><li><strong>Cognitive Biases</strong>: Understanding how biases affect your trading decisions.</li><li><strong>Developing Discipline</strong>: Building routines that support consistent execution.</li><li><strong>Mindfulness Techniques</strong>: Practical exercises to maintain focus and emotional control.</li></ul><p>Watch this recorded webinar to learn valuable techniques for improving your trading psychology.</p>',
                'estimated_duration': 90,
                'featured': False
            },
            {
                'title': 'Economic Indicators and Their Impact on Forex',
                'description': 'Comprehensive guide to major economic indicators and how they influence currency markets.',
                'category': 'Fundamental Analysis',
                'resource_type': 'article',
                'access_level': 'basic',
                'content': '<h2>Economic Indicators and Their Impact on Forex</h2><p>Economic indicators are statistical data points that provide insights into the economic performance of a country or region. These indicators can significantly impact currency values.</p><h3>Major Economic Indicators</h3><ul><li><strong>Interest Rates</strong>: How central bank decisions affect currency strength.</li><li><strong>GDP (Gross Domestic Product)</strong>: The relationship between economic growth and currency valuation.</li><li><strong>Employment Reports</strong>: How job data influences market sentiment.</li><li><strong>Inflation Metrics</strong>: The impact of CPI and other inflation measures on monetary policy and currencies.</li></ul><p>This article explains how to interpret these indicators and incorporate them into your trading strategy.</p>',
                'estimated_duration': 60,
                'featured': False
            },
            {
                'title': 'Scalping Strategies for MetaTrader 5',
                'description': 'Advanced scalping techniques optimized for the MetaTrader 5 platform, including custom indicator setups.',
                'category': 'Technical Analysis',
                'resource_type': 'pdf',
                'access_level': 'pro',
                'content': '<h2>Scalping Strategies for MetaTrader 5</h2><p>Scalping is a trading style that specializes in profiting from small price changes, making a fast profit on these small price changes.</p><h3>Scalping Techniques Covered</h3><ul><li><strong>1-Minute Chart Setups</strong>: Specific indicator combinations for ultra-short-term trading.</li><li><strong>Order Flow Scalping</strong>: Using depth of market data to identify short-term opportunities.</li><li><strong>News Scalping</strong>: Techniques for trading during high-volatility news events.</li><li><strong>Risk Management for Scalpers</strong>: Specialized position sizing and stop placement for high-frequency trading.</li></ul><p>This premium PDF includes detailed MetaTrader 5 setup instructions and 10 ready-to-use scalping templates.</p>',
                'estimated_duration': 120,
                'featured': False
            },
            {
                'title': 'Backtesting and Optimizing Expert Advisors',
                'description': 'Learn advanced techniques for testing and optimizing your trading robots to ensure reliable performance in live markets.',
                'category': 'Expert Advisor Development',
                'resource_type': 'webinar',
                'access_level': 'pro',
                'video_url': 'https://www.youtube.com/embed/dQw4w9WgXcQ',
                'content': '<h2>Backtesting and Optimizing Expert Advisors</h2><p>Proper backtesting and optimization are crucial steps in developing reliable Expert Advisors that can perform well in live market conditions.</p><h3>Webinar Content</h3><ul><li><strong>Quality Data Sources</strong>: Ensuring your backtest uses accurate historical data.</li><li><strong>Optimization Parameters</strong>: Identifying which variables to optimize and which to leave fixed.</li><li><strong>Avoiding Curve-Fitting</strong>: Techniques to ensure your EA is robust across different market conditions.</li><li><strong>Walk-Forward Analysis</strong>: Advanced testing methodologies to validate EA performance.</li><li><strong>Monte Carlo Simulation</strong>: Using statistical methods to assess strategy reliability.</li></ul><p>This pro-level webinar includes access to proprietary optimization tools and frameworks.</p>',
                'estimated_duration': 150,
                'featured': False
            }
        ]

        # Create sample PDF content
        sample_pdf_content = b'%PDF-1.4\n1 0 obj\n<</Type/Catalog/Pages 2 0 R>>\nendobj\n2 0 obj\n<</Type/Pages/Kids[3 0 R]/Count 1>>\nendobj\n3 0 obj\n<</Type/Page/MediaBox[0 0 612 792]/Resources<<>>/Contents 4 0 R/Parent 2 0 R>>\nendobj\n4 0 obj\n<</Length 22>>\nstream\nBT\n/F1 12 Tf\n100 700 Td\n(Sample PDF for Learning Center) Tj\nET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f\n0000000009 00000 n\n0000000053 00000 n\n0000000102 00000 n\n0000000199 00000 n\ntrailer\n<</Size 5/Root 1 0 R>>\nstartxref\n270\n%%EOF'

        for resource_data in resources:
            # Get the category
            category = LearningCategory.objects.get(name=resource_data['category'])
            
            # Create the resource
            resource, created = LearningResource.objects.get_or_create(
                title=resource_data['title'],
                defaults={
                    'slug': slugify(resource_data['title']),
                    'category': category,
                    'description': resource_data['description'],
                    'content': resource_data.get('content', ''),
                    'resource_type': resource_data['resource_type'],
                    'access_level': resource_data['access_level'],
                    'video_url': resource_data.get('video_url', ''),
                    'estimated_duration': resource_data['estimated_duration'],
                    'featured': resource_data.get('featured', False)
                }
            )
            
            # Add a sample PDF file for PDF resources
            if created and resource_data['resource_type'] == 'pdf':
                # Create media/learning_resources directory if it doesn't exist
                pdf_dir = os.path.join(settings.MEDIA_ROOT, 'learning_resources')
                os.makedirs(pdf_dir, exist_ok=True)
                
                # Create a sample PDF file
                file_name = f"{slugify(resource_data['title'])}.pdf"
                resource.file.save(file_name, ContentFile(sample_pdf_content))
            
            if created:
                self.stdout.write(self.style.SUCCESS(f'Created resource: {resource.title}'))
            else:
                self.stdout.write(self.style.WARNING(f'Resource already exists: {resource.title}'))
        
        self.stdout.write(self.style.SUCCESS('Learning content creation completed!'))
