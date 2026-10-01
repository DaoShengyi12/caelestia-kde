pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services

// CPU, GPU, memory and disk use, plus network speed when there is room.
Item {
    id: root

    property var frame
    property var controller

    readonly property bool showNetwork: height > 200

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Gpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    ServiceRef {
        service: NetworkUsage
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.small

        Meter {
            icon: "memory"
            label: qsTr("CPU")
            value: Cpu.percentage
            extra: Cpu.temperature > 0 ? Units.formatSensorTemp(Cpu.temperature) : ""
        }

        Meter {
            visible: Gpu.type !== Gpu.None && !isNaN(Gpu.percentage)
            icon: "developer_board"
            label: qsTr("GPU")
            value: Gpu.percentage
            extra: Gpu.temperature > 0 ? Units.formatSensorTemp(Gpu.temperature) : ""
        }

        Meter {
            icon: "memory_alt"
            label: qsTr("Memory")
            value: Memory.percentage
            extra: Memory.total > 0 ? Units.formatKibUsage(Memory.used, Memory.total) : ""
        }

        Meter {
            icon: "hard_disk"
            label: qsTr("Disk")
            value: Storage.percentage
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.showNetwork
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "download"
                color: Colours.palette.m3secondary
            }

            StyledText {
                Layout.fillWidth: true
                text: Units.formatBytes(NetworkUsage.downloadSpeed ?? 0, true)
            }

            MaterialIcon {
                text: "upload"
                color: Colours.palette.m3tertiary
            }

            StyledText {
                Layout.fillWidth: true
                text: Units.formatBytes(NetworkUsage.uploadSpeed ?? 0, true)
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    component Meter: RowLayout {
        id: meter

        required property string icon
        required property string label
        required property real value
        property string extra

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: meter.icon
            color: Colours.palette.m3primary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.minimumWidth: implicitWidth
                    text: meter.label
                    font: Tokens.font.label.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: meter.extra.length > 0 ? `${meter.extra} · ${Math.round((isNaN(meter.value) ? 0 : meter.value) * 100)}%` : `${Math.round((isNaN(meter.value) ? 0 : meter.value) * 100)}%`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                color: Qt.alpha(Colours.palette.m3onSurface, 0.15)

                StyledRect {
                    width: parent.width * Math.max(0, Math.min(1, isNaN(meter.value) ? 0 : meter.value))
                    height: parent.height
                    radius: parent.radius
                    color: meter.value > 0.85 ? Colours.palette.m3error : Colours.palette.m3primary

                    Behavior on width {
                        Anim {}
                    }
                }
            }
        }
    }
}
