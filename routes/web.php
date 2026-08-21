<?php

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Route;

Route::inertia('/', 'welcome')->name('home');

Route::get('/', function () {
    return response()->json(['status' => 'code change']);
});

Route::prefix('demo')->group(function () {
    Route::get('/fast', fn () => response()->json(['ok' => true]));

    Route::get('/slow', function () {
        usleep(random_int(300_000, 800_000));

        return response()->json(['ok' => true]);
    });

    Route::get('/variable', function () {
        usleep(random_int(10_000, 1_200_000));

        return response()->json(['ok' => true]);
    });

    Route::get('/error', function () {
        Log::error('Simulated failure on demo/error route');

        return response()->json(['error' => 'simulated failure'], 500);
    });
});
