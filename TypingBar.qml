import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// io.github.rawritude.typing — minimal multiline bottom typing bar.
//
// Summon/toggle:  omarchy-shell shell toggle io.github.rawritude.typing
// Clear text:     omarchy-shell -q io.github.rawritude.typing clear
// State:          omarchy-shell io.github.rawritude.typing state
//
// Bind it to a key in ~/.config/hypr/bindings.lua, e.g.:
//   o.bind("SUPER + PERIOD", "Type to clipboard",
//          "omarchy-shell shell toggle io.github.rawritude.typing")
//
// Enter copies the field to the Wayland clipboard via wl-copy (with a
// first-party OSD confirmation); Shift+Enter starts a new line. The
// card grows with the text up to 40% of the screen height, then keeps
// the caret in view while typing. Text survives between summons
// (keepLoaded), so reopening re-selects the last value; the clear
// method wipes it.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false

  readonly property color background: Color.popups.background
  readonly property color foreground: Color.popups.text
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.family
  readonly property int barWidth: Math.min(Style.space(760), panel.width - Style.space(32))
  readonly property int minBarHeight: Math.max(Style.space(44), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int maxBarHeight: Math.floor(panel.height * 0.4)

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (typeof p.text === "string") input.text = p.text
    } catch (e) {}
    root.opened = true
    Qt.callLater(function() {
      if (!root.opened) return
      scroller.contentY = 0
      input.forceActiveFocus()
      if (input.length > 0) input.selectAll()
      else input.cursorPosition = 0
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.rawritude.typing")
  }

  // Qt may represent Shift+Enter breaks as Unicode line separators
  // (U+2028/U+2029); normalize so the clipboard always gets plain \n.
  function normalize(value) {
    return String(value).replace(/[\u2028\u2029]/g, "\n")
  }

  function submit() {
    var value = normalize(input.text)
    root.dismiss()
    if (value === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
    var lines = value.split("\n").length
    var payload = JSON.stringify({ icon: "󰆏", message: lines > 1 ? "Copied " + lines + " lines" : "Copied" })
    Quickshell.execDetached(["bash", "-c", "omarchy-shell -q osd show " + Util.shellQuote(payload)])
  }

  function clearText() {
    input.clear()
    if (root.opened)
      Qt.callLater(function() {
        if (root.opened) input.forceActiveFocus()
      })
  }

  function ensureVisible() {
    var rect = input.cursorRectangle
    var maxY = Math.max(0, input.height - scroller.height)
    var target = scroller.contentY
    if (rect.y + rect.height > target + scroller.height)
      target = rect.y + rect.height - scroller.height
    else if (rect.y < target)
      target = rect.y
    scroller.contentY = Math.max(0, Math.min(maxY, target))
  }

  IpcHandler {
    target: "io.github.rawritude.typing"

    function clear(): string {
      root.clearText()
      return "ok"
    }

    function state(): string {
      return JSON.stringify({ open: root.opened, text: normalize(input.text) })
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-typing"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Invisible full-surface tap layer: a click anywhere outside the bar
    // dismisses it. The bar swallows clicks inside itself (below).
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.barWidth
      height: Math.min(root.maxBarHeight, Math.max(root.minBarHeight, input.contentHeight + card.contentTopInset + card.contentBottomInset))
      radius: Style.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(48)
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.controlPaddingX

      MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
      }

      Row {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Item {
          id: field
          width: parent.width
          height: parent.height

          Text {
            id: glyph
            text: "󰆏"
            color: Util.alpha(root.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            x: 0
            y: Math.max(0, Math.round((field.height - input.contentHeight) / 2))
          }

          Flickable {
            id: scroller
            anchors.left: glyph.right
            anchors.leftMargin: Style.spacing.sm
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            clip: true
            contentWidth: width
            contentHeight: input.height
            boundsBehavior: Flickable.StopAtBounds
            // Never steals drag-selection from the editor; the caret is
            // kept in view by ensureVisible() instead.
            interactive: false

            TextEdit {
              id: input
              width: scroller.width
              height: Math.max(scroller.height, input.contentHeight)
              focus: true
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.WrapAnywhere
              selectByMouse: true
              activeFocusOnPress: true
              color: root.foreground
              selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
              selectedTextColor: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              verticalAlignment: TextEdit.AlignVCenter
              cursorDelegate: Rectangle {
                width: 2
                color: root.foreground
              }
              onCursorRectangleChanged: root.ensureVisible()
              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (event.modifiers & Qt.ShiftModifier) {
                    // Leave the event unaccepted so TextEdit inserts a
                    // native line break at the cursor.
                  } else {
                    root.submit()
                    event.accepted = true
                  }
                } else if (event.key === Qt.Key_Escape) {
                  root.dismiss()
                  event.accepted = true
                }
              }
            }
          }

          Text {
            id: placeholder
            textFormat: Text.PlainText
            anchors.fill: scroller
            visible: input.length === 0
            text: "Type, then Enter to copy — Shift+Enter for a new line"
            color: Util.alpha(root.foreground, 0.55)
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
