<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Layouts\Builders\NavAction;

/**
 * Opt-in `hidden_with_tab_presentation` on top-bar actions: iOS skips the
 * action while a custom tab presentation (a side rail) is showing, for
 * actions the presentation already offers. Unset keeps today's behavior.
 */
it('emits hidden_with_tab_presentation when set through NavAction', function () {
    $props = NavAction::make('search')->icon('search')->hiddenWithTabPresentation()->press('search')
        ->toElement()->toArray(new CallbackRegistry)['props'];

    expect($props['hidden_with_tab_presentation'])->toBeTrue();
});

it('leaves hidden_with_tab_presentation out by default', function () {
    $props = NavAction::make('search')->icon('search')->press('search')
        ->toElement()->toArray(new CallbackRegistry)['props'];

    expect($props)->not->toHaveKey('hidden_with_tab_presentation');
});

it('leaves hiddenWithTabPresentation(false) out of the wire props', function () {
    $props = NavAction::make('search')->icon('search')->hiddenWithTabPresentation(false)->press('search')
        ->toElement()->toArray(new CallbackRegistry)['props'];

    expect($props)->not->toHaveKey('hidden_with_tab_presentation');
});
