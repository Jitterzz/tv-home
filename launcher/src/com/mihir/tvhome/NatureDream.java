package com.mihir.tvhome;

import android.animation.AnimatorSet;
import android.animation.ObjectAnimator;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
import android.service.dreams.DreamService;
import android.text.format.DateFormat;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.animation.LinearInterpolator;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.TextView;

import java.io.IOException;
import java.io.InputStream;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * The launcher's nature photos as the TV's screensaver, like Apple TV's aerials: a new photo fades in every 20 seconds
 * and drifts slowly while it's up, with the time small in the corner. Pick it in Settings, or TV-Kit sets it.
 */
public class NatureDream extends DreamService {
    static final long INTERVAL_MS = 20_000;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private ImageView back, front;
    private TextView clock;
    private String[] photos = new String[0];
    private int index;
    private boolean running;
    private AnimatorSet drift;

    private final Runnable next = this::showNext;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            boolean is24 = DateFormat.is24HourFormat(NatureDream.this);
            clock.setText(new SimpleDateFormat(is24 ? "H:mm" : "h:mm", Locale.getDefault()).format(new Date()));
            long now = System.currentTimeMillis();
            handler.postDelayed(this, 60_000 - now % 60_000 + 200);
        }
    };

    @Override
    public void onAttachedToWindow() {
        super.onAttachedToWindow();
        setInteractive(false);
        setFullscreen(true);
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        back = layer();
        front = layer();
        root.addView(back, new FrameLayout.LayoutParams(-1, -1));
        root.addView(front, new FrameLayout.LayoutParams(-1, -1));
        clock = new TextView(this);
        clock.setTextColor(0xE6FFFFFF);
        clock.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        clock.setTypeface(Typeface.create("sans-serif-thin", Typeface.NORMAL));
        clock.setShadowLayer(16, 0, 2, 0x99000000);
        int m = Math.round(40 * getResources().getDisplayMetrics().density);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.START);
        lp.setMargins(m, 0, 0, m);
        root.addView(clock, lp);
        setContentView(root);
        try {
            String[] list = getAssets().list("wallpapers");
            if (list != null) photos = list;
        } catch (IOException ignored) { }
        if (photos.length > 0) index = (int) ((System.currentTimeMillis() / INTERVAL_MS) % photos.length);
    }

    @Override
    public void onDreamingStarted() {
        super.onDreamingStarted();
        running = true;
        tick.run();
        showNext();
    }

    @Override
    public void onDreamingStopped() {
        running = false;
        handler.removeCallbacksAndMessages(null);
        if (drift != null) drift.cancel();
        super.onDreamingStopped();
    }

    @Override
    public void onDetachedFromWindow() {
        running = false;
        handler.removeCallbacksAndMessages(null);
        super.onDetachedFromWindow();
    }

    private ImageView layer() {
        ImageView v = new ImageView(this);
        v.setScaleType(ImageView.ScaleType.CENTER_CROP);
        return v;
    }

    /** Decodes the next photo off the main thread, then fades it in. */
    private void showNext() {
        handler.removeCallbacks(next);
        if (!running || photos.length == 0) return;
        String name = "wallpapers/" + photos[index % photos.length];
        index++;
        new Thread(() -> {
            Bitmap bm = null;
            try (InputStream in = getAssets().open(name)) {
                BitmapFactory.Options o = new BitmapFactory.Options();
                o.inPreferredConfig = Bitmap.Config.RGB_565;
                bm = BitmapFactory.decodeStream(in, null, o);
            } catch (IOException ignored) { }
            Bitmap result = bm;
            handler.post(() -> show(result));
        }).start();
        handler.postDelayed(next, INTERVAL_MS);
    }

    private void show(Bitmap bm) {
        if (bm == null || !running) return;
        ImageView old = front;
        front = back;
        back = old;
        front.bringToFront();
        clock.bringToFront();
        if (drift != null) drift.cancel();
        front.setScaleX(1f);
        front.setScaleY(1f);
        front.setImageBitmap(bm);
        front.setAlpha(0f);
        ImageView fading = back;
        front.animate().alpha(1f).setDuration(2000).withEndAction(() -> fading.setImageDrawable(null)).start();
        drift = new AnimatorSet();
        drift.playTogether(
                ObjectAnimator.ofFloat(front, View.SCALE_X, 1f, 1.06f),
                ObjectAnimator.ofFloat(front, View.SCALE_Y, 1f, 1.06f));
        drift.setDuration(INTERVAL_MS + 2500);
        drift.setInterpolator(new LinearInterpolator());
        drift.start();
    }
}
