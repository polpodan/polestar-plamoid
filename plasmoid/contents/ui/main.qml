/*
 * Polestar Hub — KDE Plasma 6  v1.7
 * - Image au-dessus du contenu scrollable (plus derrière)
 * - KPackageStructure corrigé dans metadata.json
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    property var    carData:   null
    property bool   loading:   true
    property string lastError: ""
    property bool   showSettings: false

    readonly property string apiBase: "http://127.0.0.1:47268"

    // Formulaire settings
    property string editEmail: ""
    property string editPass:  ""
    property string editVin:   ""

    Timer {
        interval: 10000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: loadData()
    }

    function loadData() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBase + "/data")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var p = JSON.parse(xhr.responseText)
                    carData = p
                    if (p.status === "loading" || p.status === "connecting") {
                        lastError = ""; loading = true
                    } else if (p.status === "error") {
                        lastError = p.error || "Erreur inconnue"; loading = false
                    } else {
                        lastError = ""; loading = false
                    }
                } catch(e) {
                    lastError = "Réponse invalide du daemon"; loading = false
                }
            } else {
                lastError = "Daemon non démarré.\nLancez: systemctl --user start polestar-plasmoid"
                loading = false
            }
        }
        xhr.send()
    }

    function saveConfig() {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", apiBase + "/config")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                showSettings = false
                loading = true
                loadData()
            } else {
                lastError = "Erreur lors de la sauvegarde"
            }
        }
        var payload = {}
        if (editEmail) payload.username = editEmail
        if (editPass)  payload.password = editPass
        if (editVin)   payload.vin      = editVin
        xhr.send(JSON.stringify(payload))
    }

    // ── Icône compacte ────────────────────────────────────────────────────────
    compactRepresentation: Item {
        implicitWidth:  Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        Kirigami.Icon {
            anchors.fill: parent; anchors.margins: 2
            source: Qt.resolvedUrl("../icons/polestar.svg"); fallback: "car"
            opacity: loading ? 0.4 : 1.0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Rectangle {
            visible: !loading && carData && carData.status === "ok"
                     && carData.battery && carData.battery.level_pct !== null
            anchors { bottom: parent.bottom; right: parent.right; bottomMargin: -1; rightMargin: -2 }
            width: lbl.implicitWidth + 5
            height: Kirigami.Units.gridUnit * 0.72
            radius: 3
            color: batteryColor(carData && carData.battery ? carData.battery.level_pct : 0)
            PlasmaComponents.Label {
                id: lbl; anchors.centerIn: parent
                text: (carData && carData.battery) ? (carData.battery.level_pct + "%") : "?"
                font.pixelSize: parent.height * 0.72; font.bold: true; color: "white"
            }
        }

        PlasmaComponents.BusyIndicator {
            anchors.centerIn: parent; visible: loading; running: loading
            width: parent.width * 0.7; height: width
        }

        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }
    }

    // ── Popup hub ─────────────────────────────────────────────────────────────
    fullRepresentation: PlasmaExtras.Representation {
        id: fullRep
        implicitWidth:  Kirigami.Units.gridUnit * 22
        implicitHeight: Kirigami.Units.gridUnit * 34

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Icon {
                    source: Qt.resolvedUrl("../icons/polestar.svg"); fallback: "car"
                    width: Kirigami.Units.iconSizes.small; height: width
                }
                PlasmaExtras.Heading {
                    level: 3
                    text: (carData && carData.car && carData.car.model) ? carData.car.model : "Polestar"
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: (carData && carData.last_update)
                          ? Qt.formatTime(new Date(carData.last_update), "hh:mm") : ""
                    opacity: 0.6; font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                PlasmaComponents.ToolButton {
                    icon.name: showSettings ? "go-previous" : "configure"
                    display: QQC2.AbstractButton.IconOnly
                    PlasmaComponents.ToolTip.text: showSettings ? "Retour" : "Réglages"
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: {
                        if (!showSettings && carData && carData.car) {
                            editEmail = "" // Laisser vide si inchangé
                            editPass = ""
                            editVin = carData.car.vin || ""
                        }
                        showSettings = !showSettings
                    }
                }
                PlasmaComponents.ToolButton {
                    visible: !showSettings
                    icon.name: "view-refresh"; display: QQC2.AbstractButton.IconOnly
                    PlasmaComponents.ToolTip.text: "Rafraîchir"
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: { loading = true; loadData() }
                }
            }
        }

        // ── Contenu : image fixe + cartes scrollables ─────────────────────────
        contentItem: ColumnLayout {
            spacing: 0

            // ── Mode Configuration ─────────────────────────────────────────────
            Flickable {
                visible: showSettings
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: settingsCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: settingsCol
                    width: parent.width - Kirigami.Units.largeSpacing * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Kirigami.Units.largeSpacing

                    Item { height: Kirigami.Units.mediumSpacing }

                    PlasmaExtras.Heading { text: "Paramètres API"; level: 4 }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        PlasmaComponents.Label { text: "Email Polestar ID"; opacity: 0.6 }
                        PlasmaComponents.TextField {
                            Layout.fillWidth: true
                            placeholderText: (carData && carData.car && carData.car.username) || "email@exemple.com"
                            onTextChanged: editEmail = text
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        PlasmaComponents.Label { text: "Mot de passe"; opacity: 0.6 }
                        PlasmaComponents.TextField {
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: "••••••••"
                            onTextChanged: editPass = text
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        PlasmaComponents.Label { text: "VIN du véhicule"; opacity: 0.6 }
                        PlasmaComponents.TextField {
                            Layout.fillWidth: true
                            text: editVin
                            placeholderText: "Auto-détection si vide"
                            onTextChanged: editVin = text
                        }
                    }

                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: "Sauvegarder la configuration"
                        highlighted: true
                        onClicked: saveConfig()
                    }

                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        type: Kirigami.MessageType.Information
                        text: "Le daemon redémarrera la connexion après sauvegarde."
                        visible: true
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Photo de la voiture (fixe, hors du scroll) ────────────────────
            Item {
                visible: !showSettings
                Layout.fillWidth: true
                // Hauteur dynamique selon ratio 600×386, 0 si image non chargée
                Layout.preferredHeight: carImg.status === Image.Ready
                                        ? Math.round(width * 386 / 600) : 0
                clip: true

                Image {
                    id: carImg
                    anchors.fill: parent
                    source: apiBase + "/car.jpg"
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    cache: false
                }

                // Dégradé bas pour fondu
                Rectangle {
                    visible: carImg.status === Image.Ready
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 36
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Kirigami.Theme.backgroundColor }
                    }
                }
            }

            // ── Cartes scrollables ─────────────────────────────────────────────
            Flickable {
                visible: !showSettings
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: col.implicitHeight
                clip: true

                ColumnLayout {
                    id: col
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing

                    // Petit espace en haut
                    Item { height: Kirigami.Units.smallSpacing }

                    // Chargement
                    ColumnLayout {
                        visible: loading; Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                        PlasmaComponents.BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: true }
                        PlasmaComponents.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Connexion à l'API Polestar\u2026"; opacity: 0.7
                        }
                    }

                    // Erreur
                    Kirigami.InlineMessage {
                        visible: !loading && lastError !== ""; Layout.fillWidth: true
                        type: Kirigami.MessageType.Error; text: lastError; showCloseButton: false
                    }

                    // ── Batterie ──────────────────────────────────────────────
                    Kirigami.Card {
                        visible: !loading && carData && carData.status === "ok"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Kirigami.Icon { source: "battery"; width: Kirigami.Units.iconSizes.small; height: width }
                                PlasmaComponents.Label { text: "Batterie"; font.bold: true; Layout.fillWidth: true }
                                PlasmaComponents.Label {
                                    text: chargingStatusText(); color: chargingStatusColor()
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4
                                color: Kirigami.Theme.backgroundColor
                                border.color: Kirigami.Theme.textColor; border.width: 1
                                Rectangle {
                                    property int pct: (carData && carData.battery) ? (carData.battery.level_pct || 0) : 0
                                    width: Math.max(radius * 2, parent.width * pct / 100)
                                    height: parent.height; radius: parent.radius
                                    color: batteryColor(pct)
                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                }
                            }

                            PlasmaExtras.Heading {
                                Layout.alignment: Qt.AlignHCenter; level: 2
                                text: (carData && carData.battery && carData.battery.level_pct !== null)
                                      ? carData.battery.level_pct + "%" : "--"
                            }

                            GridLayout {
                                Layout.fillWidth: true; columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: 4
                                InfoRow { label: "🛣️  Autonomie";    value: fmtKm(carData && carData.battery ? carData.battery.range_km : null) }
                                InfoRow { label: "📡  Plein à 100%"; value: fmtKm(carData && carData.battery ? carData.battery.estimated_full_range_km : null) }
                                InfoRow {
                                    visible: carData && carData.battery && carData.battery.charge_limit_pct !== null
                                    label: "🎯  Limite charge"; value: (carData && carData.battery) ? carData.battery.charge_limit_pct + "%" : "--"
                                }
                                InfoRow {
                                    label: "⏱️  Charge complète"
                                    value: {
                                        if (!carData || !carData.battery) return "--"
                                        var m = carData.battery.time_to_full_min
                                        if (m === null || m === undefined) return "--"
                                        if (m === 0) return "Chargé \u2713"
                                        var h = Math.floor(m / 60)
                                        return h > 0 ? (h + "h " + (m % 60) + "min") : (m + " min")
                                    }
                                }
                                InfoRow {
                                    visible: carData && carData.battery
                                             && carData.battery.charging_power_w !== null
                                             && carData.battery.charging_power_w !== undefined
                                    label: "⚡  Puissance charge"
                                    value: (carData && carData.battery && carData.battery.charging_power_w)
                                           ? (carData.battery.charging_power_w / 1000).toFixed(1) + " kW" : "--"
                                }
                                InfoRow {
                                    visible: carData && carData.battery
                                             && carData.battery.avg_consumption_kwh100 !== null
                                             && carData.battery.avg_consumption_kwh100 !== undefined
                                    label: "📊  Conso. moy."
                                    value: carData && carData.battery && carData.battery.avg_consumption_kwh100 !== null
                                           ? carData.battery.avg_consumption_kwh100 + " kWh/100" : "--"
                                }
                            }
                        }
                    }

                    // ── Sécurité & Confort ────────────────────────────────────
                    Kirigami.Card {
                        visible: !loading && carData && carData.status === "ok" && carData.safety
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Kirigami.Icon { source: "security-high"; width: Kirigami.Units.iconSizes.small; height: width }
                                PlasmaComponents.Label { text: "Sécurité & Confort"; font.bold: true; Layout.fillWidth: true }
                            }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: 4
                                InfoRow {
                                    label: "🔒  Verrouillage"
                                    value: {
                                        if (!carData.safety || carData.safety.is_locked === null) return "--"
                                        return carData.safety.is_locked ? "Verrouillée" : "Déverrouillée ⚠️"
                                    }
                                }
                                InfoRow {
                                    label: "🌡️  Climatisation"
                                    value: {
                                        if (!carData.safety || carData.safety.climate_active === null) return "--"
                                        return carData.safety.climate_active ? "En cours ❄️" : "Arrêtée"
                                    }
                                }
                                InfoRow {
                                    label: "🚪  Portes"
                                    value: {
                                        if (!carData.safety || carData.safety.doors_open === null) return "--"
                                        return carData.safety.doors_open ? "Ouvertes ⚠️" : "Fermées"
                                    }
                                }
                                InfoRow {
                                    label: "🪟  Fenêtres"
                                    value: {
                                        if (!carData.safety || carData.safety.windows_open === null) return "--"
                                        return carData.safety.windows_open ? "Ouvertes ⚠️" : "Fermées"
                                    }
                                }
                            }
                        }
                    }

                    // ── Odomètre ──────────────────────────────────────────────
                    Kirigami.Card {
                        visible: !loading && carData && carData.status === "ok"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Kirigami.Icon { source: "map-globe"; width: Kirigami.Units.iconSizes.small; height: width }
                                PlasmaComponents.Label { text: "Kilométrage"; font.bold: true; Layout.fillWidth: true }
                            }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: 4
                                InfoRow {
                                    label: "📍  Odomètre total"
                                    value: (carData && carData.odometer && carData.odometer.km !== null)
                                           ? Number(carData.odometer.km).toLocaleString(Qt.locale("fr-CA"), "f", 0) + " km" : "--"
                                }
                                InfoRow {
                                    visible: carData && carData.odometer
                                             && carData.odometer.trip_auto_km !== null
                                             && carData.odometer.trip_auto_km !== undefined
                                    label: "🔄  Trip auto"
                                    value: (carData && carData.odometer && carData.odometer.trip_auto_km !== null)
                                           ? carData.odometer.trip_auto_km + " km" : "--"
                                }
                            }
                        }
                    }

                    // ── Santé ─────────────────────────────────────────────────
                    Kirigami.Card {
                        visible: !loading && carData && carData.status === "ok"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Kirigami.Icon { source: "checkmark"; width: Kirigami.Units.iconSizes.small; height: width }
                                PlasmaComponents.Label { text: "Santé véhicule"; font.bold: true; Layout.fillWidth: true }
                                PlasmaComponents.Label {
                                    text: healthSummaryText(); color: healthSummaryColor()
                                    font.bold: true; font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: 4
                                InfoRow {
                                    label: "🔧  Prochain entretien"
                                    value: {
                                        if (!carData || !carData.health) return "--"
                                        var p = []
                                        if (carData.health.days_to_service != null)
                                            p.push(carData.health.days_to_service + " j")
                                        if (carData.health.distance_to_service_km != null)
                                            p.push(carData.health.distance_to_service_km + " km")
                                        return p.length ? p.join(" / ") : "--"
                                    }
                                }
                                InfoRow {
                                    label: "💧  Liquide frein"
                                    value: fmtWarning(carData && carData.health ? carData.health.brake_fluid : null)
                                }
                            }
                        }
                    }

                    // ── Raccourcis ────────────────────────────────────────────
                    Kirigami.Card {
                        visible: !loading && carData && carData.status === "ok"
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            RowLayout {
                                Kirigami.Icon { source: "internet-web-browser"; width: Kirigami.Units.iconSizes.small; height: width }
                                PlasmaComponents.Label { text: "Raccourcis"; font.bold: true; Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents.Button {
                                    Layout.fillWidth: true; text: "📱 Mon compte"
                                    PlasmaComponents.ToolTip.text: "polestar.com \u2014 Mon profil"
                                    PlasmaComponents.ToolTip.visible: hovered
                                    onClicked: Qt.openUrlExternally("https://www.polestar.com/fr-ca/login/profile/")
                                }
                                PlasmaComponents.Button {
                                    Layout.fillWidth: true; text: "🌐 Polestar CA"
                                    PlasmaComponents.ToolTip.text: "Site Polestar Canada (français)"
                                    PlasmaComponents.ToolTip.visible: hovered
                                    onClicked: Qt.openUrlExternally("https://www.polestar.com/fr-ca/")
                                }
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: "❄️ Climatisation : utilisez l'app Polestar (Android/iOS)\nou la minuterie intégrée dans la voiture."
                                opacity: 0.6; wrapMode: Text.WordWrap
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }
                    }

                    // Footer
                    PlasmaComponents.Label {
                        visible: carData && carData.car
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (!carData || !carData.car) return ""
                            var p = []
                            if (carData.car.model_year)       p.push(carData.car.model_year)
                            if (carData.car.vin)              p.push("VIN \u2026" + carData.car.vin.slice(-6))
                            if (carData.car.software_version) p.push("SW " + carData.car.software_version)
                            return p.join("  \u00b7  ")
                        }
                        opacity: 0.4; font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        wrapMode: Text.WordWrap
                    }
                    Item { height: Kirigami.Units.smallSpacing }
                }
            }
        }
    }

    component InfoRow: ColumnLayout {
        property string label: ""; property string value: "--"
        spacing: 1
        PlasmaComponents.Label { text: label; opacity: 0.6; font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
        PlasmaComponents.Label { text: value;                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize }
    }

    function fmtKm(v) { return (v === null || v === undefined) ? "--" : Math.round(v) + " km" }
    function batteryColor(pct) {
        var n = Number(pct) || 0
        return n > 50 ? "#27ae60" : n > 20 ? "#f39c12" : "#e74c3c"
    }
    function chargingStatusText() {
        if (!carData || !carData.battery) return ""
        var s = String(carData.battery.charging_status || "")
        if (s.indexOf("Charging")  >= 0) return "⚡ En charge"
        if (s.indexOf("Done")      >= 0) return "\u2705 Chargé"
        if (s.indexOf("Connected") >= 0) return "🔌 Connecté"
        if (s.indexOf("Scheduled") >= 0) return "⏰ Programmé"
        if (s.indexOf("Idle")      >= 0) return "💤 Inactif"
        return s
    }
    function chargingStatusColor() {
        if (!carData || !carData.battery) return Kirigami.Theme.textColor
        var s = String(carData.battery.charging_status || "")
        if (s.indexOf("Charging") >= 0) return "#3daee9"
        if (s.indexOf("Done")     >= 0) return "#27ae60"
        return Kirigami.Theme.textColor
    }
    function healthSummaryText() {
        if (!carData || !carData.health) return "--"
        var sw = String(carData.health.service_warning || "")
        if (sw.indexOf("No Warning") >= 0) return "\u2705 OK"
        if (sw.indexOf("Required")   >= 0) return "⚠️ Service requis"
        if (sw.indexOf("Almost")     >= 0) return "🔔 Bientôt"
        return sw
    }
    function healthSummaryColor() {
        if (!carData || !carData.health) return Kirigami.Theme.textColor
        var sw = String(carData.health.service_warning || "")
        if (sw.indexOf("No Warning") >= 0) return "#27ae60"
        if (sw.indexOf("Required")   >= 0) return "#e74c3c"
        if (sw.indexOf("Almost")     >= 0) return "#f39c12"
        return Kirigami.Theme.textColor
    }
    function fmtWarning(val) {
        if (!val) return "--"
        var s = String(val)
        if (s.indexOf("No Warning") >= 0) return "\u2705 Normal"
        if (s.indexOf("Too Low")    >= 0) return "⚠️ Bas"
        return s
    }
}
