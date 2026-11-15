package pl.znicz.znicz

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Widżet na ekran główny: najbliższa rocznica i postęp listy na Wszystkich Świętych. */
class ZniczWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.znicz_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("w_title", "Znicz"))
                setTextViewText(R.id.widget_line1, widgetData.getString("w_line1", "Otwórz aplikację, by odświeżyć"))
                setTextViewText(R.id.widget_line2, widgetData.getString("w_line2", ""))
                setTextViewText(R.id.widget_line3, widgetData.getString("w_line3", ""))
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
