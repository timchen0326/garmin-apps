import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Simple list menu driven by UP/DOWN/START/BACK and taps.
// The built-in Menu2 on the S62 only scrolls by swiping, so buttons can't
// reach items below the fold.
class ChoiceMenu extends WatchUi.View {

    var title as String;
    var labels as Array<String>;
    var ids as Array<Symbol>;
    var index as Number = 0;

    function initialize(title as String, labels as Array<String>, ids as Array<Symbol>) {
        View.initialize();
        self.title = title;
        self.labels = labels;
        self.ids = ids;
    }

    function move(delta as Number) as Void {
        var n = labels.size();
        index = (index + delta + n) % n;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.15, Graphics.FONT_XTINY, title, center);

        // Selected item in a highlight bar, neighbours above and below
        var barH = h * 0.2;
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(w * 0.08, h * 0.52 - barH / 2, w * 0.84, barH, 10);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.52, Graphics.FONT_MEDIUM, labels[index], center);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (index > 0) {
            dc.drawText(cx, h * 0.31, Graphics.FONT_SMALL, labels[index - 1], center);
        }
        if (index < labels.size() - 1) {
            dc.drawText(cx, h * 0.73, Graphics.FONT_SMALL, labels[index + 1], center);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.88, Graphics.FONT_XTINY, (index + 1) + "/" + labels.size(), center);
    }
}

class ChoiceMenuDelegate extends WatchUi.BehaviorDelegate {

    private var _menu as ChoiceMenu;
    private var _handler as Method(id as Symbol) as Void;

    function initialize(menu as ChoiceMenu, handler as Method(id as Symbol) as Void) {
        BehaviorDelegate.initialize();
        _menu = menu;
        _handler = handler;
    }

    function onPreviousPage() as Boolean {
        _menu.move(-1);
        return true;
    }

    function onNextPage() as Boolean {
        _menu.move(1);
        return true;
    }

    function onSelect() as Boolean {
        choose();
        return true;
    }

    // Tap above/below the bar moves, tap on the bar selects
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var y = evt.getCoordinates()[1];
        var h = System.getDeviceSettings().screenHeight;
        if (y < h * 0.42) {
            _menu.move(-1);
        } else if (y > h * 0.62) {
            _menu.move(1);
        } else {
            choose();
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    private function choose() as Void {
        var id = _menu.ids[_menu.index];
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        _handler.invoke(id);
    }
}

function pushChoiceMenu(title as String, labels as Array<String>, ids as Array<Symbol>,
        handler as Method(id as Symbol) as Void) as Void {
    var menu = new ChoiceMenu(title, labels, ids);
    WatchUi.pushView(menu, new ChoiceMenuDelegate(menu, handler), WatchUi.SLIDE_UP);
}

// While recording, the first (default) item is "Keep going", so pressing
// START twice by accident leaves the session running.
function pushEndMenu(model as BoulderSession) as Void {
    if (model.isRecording()) {
        pushChoiceMenu("Recording",
            ["Keep going", "Pause", "Save", "Discard"],
            [:resume, :pause, :save, :discard],
            new EndHandler(model).method(:onChoice));
    } else {
        pushChoiceMenu("Paused",
            ["Resume", "Save", "Discard"],
            [:resume, :save, :discard],
            new EndHandler(model).method(:onChoice));
    }
}

class EndHandler {

    private var _model as BoulderSession;

    function initialize(model as BoulderSession) {
        _model = model;
    }

    function onChoice(id as Symbol) as Void {
        if (id == :save) {
            _model.save();
            buzz(500);
            WatchUi.switchToView(new SummaryView(_model), new SummaryDelegate(), WatchUi.SLIDE_UP);
        } else if (id == :resume) {
            if (!_model.isRecording()) {
                _model.resume();
                buzz(100);
            }
            WatchUi.requestUpdate();
        } else if (id == :pause) {
            _model.pause();
            buzz(100);
            WatchUi.requestUpdate();
        } else if (id == :discard) {
            pushChoiceMenu("Discard session?",
                ["No", "Yes, discard"],
                [:no, :yes],
                method(:onDiscardChoice));
        }
    }

    function onDiscardChoice(id as Symbol) as Void {
        if (id == :yes) {
            _model.discard();
            System.exit();
        }
    }
}
