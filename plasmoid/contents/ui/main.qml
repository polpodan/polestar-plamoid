/*
 * Polestar Plasmoid — KDE Plasma 6
 * v1.1 — Corrections:
 *  - Qt.resolvedUrl() au lieu de plasmoid.file() (supprimé Plasma 6)
 *  - Lecture données via HTTP localhost:47268 (file:// bloqué par QML)
 *  - SVG réduit
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

    property var carData: null
    property bool loading: true
    property string lastError: ""
    property bool climateActive: false
    property bool climatePending: false

    readonly property string apiBase: "http://127.0.0.1:47268"

    Timer {
        id: refreshTimer
        interval: 10000
        running: true
        repeat: true
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
                    var parsed = JSON.parse(xhr.responseText)
                    carData = parsed
                    if (parsed.status === "loading" || parsed.status === "connecting") {
                        lastError = ""
                        loading = true
                    } else if (parsed.status === "error") {
                        lastError = parsed.error || "Erreur inconnue"
                        loading = false
                    } else {
                        lastError = ""
                        loading = false
                    }
                } catch(e) {
                    lastError = "Réponse invalide du daemon"
                    loading = false
                }
            } else {
                lastError = "Daemon non démarré (port 47268)\nLancez: systemctl --user start polestar-plasmoid"
                loading = false
            }
        }
        xhr.send()
    }

    function toggleClimate() {
        climatePending = true
        climateErrorText.visible = false
        var action = climateActive ? "stop" : "start"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", apiBase + "/climate/" + action)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            climatePending = false
            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    if (resp.status === "ok") {
                        climateActive = !climateActive
                    } else {
                        climateErrorText.text = "Erreur: " + (resp.error || "inconnue")
                        climateErrorText.visible = true
                    }
                } catch(e) {}
            } else {
                climateErrorText.text = "Daemon inaccessible"
                climateErrorText.visible = true
            }
        }
        xhr.send()
    }

    // ── Icône compacte dans le panneau ────────────────────────────────────────
    compactRepresentation: Item {
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: 2
            source: Qt.resolvedUrl("../icons/polestar.svg")
            fallback: "car"
            opacity: loading ? 0.4 : 1.0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Rectangle {
            visible: !loading && carData && carData.status === "ok"
                     && carData.battery && carData.battery.level_pct !== null
            anchors { bottom: parent.bottom; right: parent.right; bottomMargin: -1; rightMargin: -2 }
            width: badgeLabel.implicitWidth + 5
            height: Kirigami.Units.gridUnit * 0.72
            radius: 3
            color: {
                var pct = (carData && carData.battery) ? (carData.battery.level_pct || 0) : 0
                return pct > 50 ? "#27ae60" : pct > 20 ? "#f39c12" : "#e74c3c"
            }
            PlasmaComponents.Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: (carData && carData.battery) ? (carData.battery.level_pct + "%") : "?"
                font.pixelSize: parent.height * 0.72
                font.bold: true
                color: "white"
            }
        }

        PlasmaComponents.BusyIndicator {
            anchors.centerIn: parent
            visible: loading
            running: loading
            width: parent.width * 0.7
            height: width
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ── Popup hub ─────────────────────────────────────────────────────────────
    fullRepresentation: PlasmaExtras.Representation {
        implicitWidth: Kirigami.Units.gridUnit * 22
        implicitHeight: Kirigami.Units.gridUnit * 28

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Icon {
                    source: Qt.resolvedUrl("../icons/polestar.svg")
                    fallback: "car"
                    width: Kirigami.Units.iconSizes.small
                    height: width
                }
                PlasmaExtras.Heading {
                    level: 3
                    text: (carData && carData.car && carData.car.model) ? carData.car.model : "Polestar"
                    Layout.fillWidth: true
                }
                PlasmaComponents.Label {
                    text: carData && carData.last_update
                          ? Qt.formatTime(new Date(carData.last_update), "hh:mm") : ""
                    opacity: 0.6
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    PlasmaComponents.ToolTip.text: "Rafraîchir"
                    PlasmaComponents.ToolTip.visible: hovered
                    onClicked: { loading = true; loadData() }
                }
            }
        }

        contentItem: Flickable {
            contentHeight: col.implicitHeight
            clip: true

            ColumnLayout {
                id: col
                width: parent.width
                spacing: Kirigami.Units.largeSpacing

                // Chargement
                ColumnLayout {
                    visible: loading
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    PlasmaComponents.BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: true }
                    PlasmaComponents.Label { Layout.alignment: Qt.AlignHCenter; text: "Connexion à l'API Polestar…"; opacity: 0.7 }
                }

                // Erreur
                Kirigami.InlineMessage {
                    visible: !loading && lastError !== ""
                    Layout.fillWidth: true
                    type: Kirigami.MessageType.Error
                    text: lastError
                    showCloseButton: false
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
                                text: chargingStatusText()
                                color: chargingStatusColor()
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: Kirigami.Units.gridUnit * 0.55
                            radius: height / 2
                            color: Kirigami.Theme.backgroundColor
                            border.color: Kirigami.Theme.textColor; border.width: 1
                            Rectangle {
                                width: {
                                    var pct = carData && carData.battery ? (carData.battery.level_pct || 0) : 0
                                    return Math.max(parent.radius * 2, parent.width * pct / 100)
                                }
                                height: parent.height; radius: parent.radius
                                color: {
                                    var pct = carData && carData.battery ? (carData.battery.level_pct || 0) : 0
                                    return pct > 50 ? "#27ae60" : pct > 20 ? "#f39c12" : "#e74c3c"
                                }
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }

                        PlasmaExtras.Heading {
                            Layout.alignment: Qt.AlignHCenter
                            level: 2
                            text: (carData && carData.battery && carData.battery.level_pct !== null)
                                  ? carData.battery.level_pct + "%" : "--"
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: 4

                            InfoRow { label: "🛣️ Autonomie"; value: formatKm(carData && carData.battery ? carData.battery.range_km : null) }
                            InfoRow { label: "📡 Autonomie 100%"; value: formatKm(carData && carData.battery ? carData.battery.estimated_full_range_km : null) }
                            InfoRow {
                                label: "⏱️ Charge complète"
                                value: {
                                    if (!carData || !carData.battery || carData.battery.time_to_full_min === null || carData.battery.time_to_full_min === undefined) return "--"
                                    var min = carData.battery.time_to_full_min
                                    if (min === 0) return "Chargé ✓"
                                    var h = Math.floor(min / 60); var m = min % 60
                                    return h > 0 ? h + "h " + m + "min" : m + " min"
                                }
                            }
                            InfoRow {
                                label: "⚡ Puissance charge"
                                value: (carData && carData.battery && carData.battery.charging_power_w)
                                       ? (carData.battery.charging_power_w / 1000).toFixed(1) + " kW" : "--"
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
                            Layout.fillWidth: true; columns: 2; columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: 4
                            InfoRow {
                                label: "📍 Odomètre total"
                                value: (carData && carData.odometer && carData.odometer.km !== null)
                                       ? Number(carData.odometer.km).toLocaleString(Qt.locale("fr-CA"), 'f', 0) + " km" : "--"
                            }
                            InfoRow {
                                label: "🔄 Trip auto"
                                value: (carData && carData.odometer && carData.odometer.trip_auto_km !== null)
                                       ? carData.odometer.trip_auto_km + " km" : "--"
                            }
                            InfoRow {
                                label: "📊 Conso. moy."
                                value: (carData && carData.battery && carData.battery.avg_consumption_kwh100 !== null)
                                       ? carData.battery.avg_consumption_kwh100 + " kWh/100" : "--"
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
                            Layout.fillWidth: true; columns: 2; columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: 4
                            InfoRow {
                                label: "🔧 Prochain entretien"
                                value: {
                                    if (!carData || !carData.health) return "--"
                                    var p = []
                                    if (carData.health.days_to_service != null) p.push(carData.health.days_to_service + " j")
                                    if (carData.health.distance_to_service_km != null) p.push(carData.health.distance_to_service_km + " km")
                                    return p.length ? p.join(" / ") : "--"
                                }
                            }
                            InfoRow { label: "💧 Liquide frein"; value: formatWarning(carData && carData.health ? carData.health.brake_fluid : null) }
                        }
                    }
                }

                // ── Contrôle climatisation ────────────────────────────────
                Kirigami.Card {
                    visible: !loading && carData && carData.status === "ok"
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        RowLayout {
                            Kirigami.Icon { source: "media-playback-start"; width: Kirigami.Units.iconSizes.small; height: width }
                            PlasmaComponents.Label { text: "Contrôle à distance"; font.bold: true; Layout.fillWidth: true }
                        }
                        PlasmaComponents.Button {
                            Layout.fillWidth: true
                            text: climatePending ? "⏳ En cours…" : climateActive ? "🌡️ Arrêter la climatisation" : "❄️ Démarrer la climatisation"
                            enabled: climatePending !== true
                            highlighted: climateActive === true
                            onClicked: toggleClimate()
                        }
                        PlasmaComponents.Label {
                            id: climateErrorText
                            visible: false
                            Layout.fillWidth: true
                            color: Kirigami.Theme.negativeTextColor
                            wrapMode: Text.WordWrap
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                    }
                }

                // Footer
                PlasmaComponents.Label {
                    visible: carData && carData.car
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        if (!carData || !carData.car) return ""
                        var p = []
                        if (carData.car.model_year) p.push(carData.car.model_year)
                        if (carData.car.vin) p.push("VIN …" + carData.car.vin.slice(-6))
                        if (carData.car.software_version) p.push("SW " + carData.car.software_version)
                        return p.join("  ·  ")
                    }
                    opacity: 0.45
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    wrapMode: Text.WordWrap
                }

                Item { height: Kirigami.Units.smallSpacing }
            }
        }
    }

    // ── Composant réutilisable ────────────────────────────────────────────────
    component InfoRow: ColumnLayout {
        property string label: ""
        property string value: "--"
        spacing: 1
        PlasmaComponents.Label { text: label; opacity: 0.6; font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
        PlasmaComponents.Label { text: value; font.pixelSize: Kirigami.Theme.defaultFont.pixelSize }
    }

    // ── Utilitaires ───────────────────────────────────────────────────────────
    function formatKm(val) {
        return (val === null || val === undefined) ? "--" : Math.round(val) + " km"
    }
    function chargingStatusText() {
        if (!carData || !carData.battery) return ""
        var s = carData.battery.charging_status || ""
        if (s.includes("Charging"))  return "⚡ En charge"
        if (s.includes("Done"))      return "✅ Chargé"
        if (s.includes("Connected")) return "🔌 Connecté"
        if (s.includes("Scheduled")) return "⏰ Programmé"
        if (s.includes("Idle"))      return "💤 Inactif"
        return s
    }
    function chargingStatusColor() {
        if (!carData || !carData.battery) return Kirigami.Theme.textColor
        var s = carData.battery.charging_status || ""
        if (s.includes("Charging")) return "#3daee9"
        if (s.includes("Done"))     return "#27ae60"
        return Kirigami.Theme.textColor
    }
    function healthSummaryText() {
        if (!carData || !carData.health) return "--"
        var sw = carData.health.service_warning || ""
        if (sw.includes("No Warning")) return "✅ OK"
        if (sw.includes("Required"))   return "⚠️ Service requis"
        if (sw.includes("Almost"))     return "🔔 Bientôt"
        return sw
    }
    function healthSummaryColor() {
        if (!carData || !carData.health) return Kirigami.Theme.textColor
        var sw = carData.health.service_warning || ""
        if (sw.includes("No Warning")) return "#27ae60"
        if (sw.includes("Required"))   return "#e74c3c"
        if (sw.includes("Almost"))     return "#f39c12"
        return Kirigami.Theme.textColor
    }
    function formatWarning(val) {
        if (!val) return "--"
        if (val.includes("No Warning")) return "✅ Normal"
        if (val.includes("Too Low"))    return "⚠️ Bas"
        return val
    }
}
