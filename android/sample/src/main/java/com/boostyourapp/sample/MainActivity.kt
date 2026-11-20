package com.boostyourapp.sample

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.boostyourapp.network.BoostNetwork

/** Écran de démonstration : le contenu est réduit de la place de la bannière, la fin de la liste reste visible. */
class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(48, 48, 48, 48)
        }
        column.addView(TextView(this).apply {
            text = "BoostYourApp SDK ${BoostNetwork.version}"
            textSize = 20f
        })
        column.addView(button("Bannière en bas") { BoostNetwork.showBanner("bottom") })
        column.addView(button("Bannière en haut") { BoostNetwork.showBanner("top") })
        column.addView(button("Masquer") { BoostNetwork.hideBanner() })
        column.addView(button("Style standard") { BoostNetwork.setStyle("standard") })
        column.addView(button("Style dynamique (Néon arcade)") { BoostNetwork.setStyle("dynamic", "neon") })
        column.addView(button("Style dynamique (Rétro crème)") { BoostNetwork.setStyle("dynamic", "retro") })
        column.addView(button("Interstitiel") {
            BoostNetwork.showInterstitial { shown ->
                Toast.makeText(this, if (shown) "Interstitiel fermé" else "Pas d'interstitiel prêt", Toast.LENGTH_SHORT).show()
            }
        })
        column.addView(button("Autre écran") { startActivity(Intent(this, SecondActivity::class.java)) })
        repeat(30) { index ->
            column.addView(TextView(this).apply { text = "Contenu de l'app, ligne ${index + 1}" })
        }
        setContentView(ScrollView(this).apply { addView(column) })

        BoostNetwork.showBanner("bottom")
    }

    private fun button(label: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        setOnClickListener { onClick() }
    }
}

/** Deuxième écran : la bannière suit l'activité au premier plan. */
class SecondActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply {
            text = "Deuxième écran"
            textSize = 20f
            setPadding(48, 48, 48, 48)
        })
    }
}
