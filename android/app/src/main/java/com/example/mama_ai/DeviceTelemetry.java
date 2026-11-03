package com.example.mama_ai;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Debug;
import android.os.PowerManager;

import com.google.gson.JsonObject;

/**
 * Collects the "device envelope" used by telemetry:
 *
 *   device  : manufacturer, model, Android API, total RAM, RAM class, backend
 *   memory  : available MB, total MB, low-memory flag, process PSS
 *   thermal : Android thermal status / headroom (thermal throttling)
 *   battery : percent, temperature, charging
 *
 * Everything is best-effort and must never throw: telemetry that kills the app
 * is worse than telemetry with one missing number.
 */
final class DeviceTelemetry {
    private final Context context;
    private final ActivityManager activityManager;
    private final PowerManager powerManager;

    DeviceTelemetry(Context context) {
        this.context = context.getApplicationContext();
        this.activityManager =
                (ActivityManager) this.context.getSystemService(Context.ACTIVITY_SERVICE);
        this.powerManager =
                (PowerManager) this.context.getSystemService(Context.POWER_SERVICE);
    }

    /** One complete snapshot. Safe to call repeatedly (the app samples it). */
    JsonObject snapshot(String backend) {
        JsonObject root = new JsonObject();
        root.add("device", device(backend));
        root.add("memory", memory());
        root.add("thermal", thermal());
        root.add("battery", battery());
        return root;
    }

    JsonObject device(String backend) {
        JsonObject device = new JsonObject();
        device.addProperty("manufacturer", safe(Build.MANUFACTURER));
        device.addProperty("brand", safe(Build.BRAND));
        device.addProperty("model", safe(Build.MODEL));
        device.addProperty("device", safe(Build.DEVICE));
        device.addProperty("android_api", Build.VERSION.SDK_INT);
        device.addProperty("android_release", safe(Build.VERSION.RELEASE));
        device.addProperty("cpu_abi", cpuAbi());
        device.addProperty("cpu_cores", Runtime.getRuntime().availableProcessors());

        long totalMb = totalRamMb();
        device.addProperty("ram_total_mb", totalMb);
        device.addProperty("ram_class", ramClass(totalMb));
        device.addProperty(
                "backend",
                backend == null || backend.trim().isEmpty() ? "cpu" : backend.trim());
        device.addProperty("app_version", appVersion());
        return device;
    }

    private JsonObject memory() {
        JsonObject result = new JsonObject();
        long totalMb = 0;
        try {
            ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
            if (activityManager != null) activityManager.getMemoryInfo(info);
            totalMb = info.totalMem / (1024L * 1024L);
            result.addProperty("available_mb", info.availMem / (1024L * 1024L));
            result.addProperty("total_mb", totalMb > 0 ? totalMb : totalRamMb());
            result.addProperty("threshold_mb", info.threshold / (1024L * 1024L));
            result.addProperty("low_memory", info.lowMemory);
        } catch (Throwable ignored) {
            // Leave the numbers out rather than crash the app.
        }

        // Process PSS = how much memory THIS app is really using. This is the
        // number that tells us whether the model is about to be killed.
        try {
            Debug.MemoryInfo process = new Debug.MemoryInfo();
            Debug.getMemoryInfo(process);
            result.addProperty("process_pss_mb", process.getTotalPss() / 1024);
        } catch (Throwable ignored) {
        }
        return result;
    }

    private JsonObject thermal() {
        JsonObject result = new JsonObject();
        if (powerManager == null) return result;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                int status = powerManager.getCurrentThermalStatus();
                result.addProperty("status", status);
                result.addProperty("status_name", thermalStatusName(status));
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                float headroom = powerManager.getThermalHeadroom(0);
                if (!Float.isNaN(headroom)) {
                    result.addProperty("headroom", round1(headroom));
                }
            }
        } catch (Throwable ignored) {
        }
        return result;
    }

    private JsonObject battery() {
        JsonObject result = new JsonObject();
        try {
            Intent intent = context.registerReceiver(
                    null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (intent == null) return result;

            int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
            int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
            if (level >= 0 && scale > 0) {
                result.addProperty("percent", Math.round(level * 100f / scale));
            }

            int temperature = intent.getIntExtra(
                    BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
            if (temperature != Integer.MIN_VALUE) {
                result.addProperty("temperature_c", round1(temperature / 10.0));
            }

            int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
            result.addProperty(
                    "charging",
                    status == BatteryManager.BATTERY_STATUS_CHARGING
                            || status == BatteryManager.BATTERY_STATUS_FULL);

            int plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1);
            if (plugged >= 0) result.addProperty("plugged", plugged != 0);
        } catch (Throwable ignored) {
        }
        return result;
    }

    private long totalRamMb() {
        try {
            ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
            if (activityManager != null) activityManager.getMemoryInfo(info);
            return info.totalMem / (1024L * 1024L);
        } catch (Throwable ignored) {
            return 0L;
        }
    }

    /**
     * Turns total RAM into the class users recognise: 4GB, 6GB, 8GB...
     * Phones never report exactly 8192 MB (the OS reserves some), so we round.
     */
    private static String ramClass(long totalMb) {
        if (totalMb <= 0) return "unknown";
        double gb = totalMb / 1024.0;
        int rounded;
        if (gb <= 2.5) {
            rounded = 2;
        } else if (gb <= 3.5) {
            rounded = 3;
        } else if (gb <= 5.0) {
            rounded = 4;
        } else if (gb <= 7.0) {
            rounded = 6;
        } else if (gb <= 10.0) {
            rounded = 8;
        } else if (gb <= 14.0) {
            rounded = 12;
        } else if (gb <= 20.0) {
            rounded = 16;
        } else {
            rounded = 24;
        }
        return rounded + "GB";
    }

    private static String thermalStatusName(int status) {
        switch (status) {
            case PowerManager.THERMAL_STATUS_NONE:
                return "none";
            case PowerManager.THERMAL_STATUS_LIGHT:
                return "light";
            case PowerManager.THERMAL_STATUS_MODERATE:
                return "moderate";
            case PowerManager.THERMAL_STATUS_SEVERE:
                return "severe";
            case PowerManager.THERMAL_STATUS_CRITICAL:
                return "critical";
            case PowerManager.THERMAL_STATUS_EMERGENCY:
                return "emergency";
            case PowerManager.THERMAL_STATUS_SHUTDOWN:
                return "shutdown";
            default:
                return "unknown";
        }
    }

    private static String cpuAbi() {
        try {
            return Build.SUPPORTED_ABIS.length > 0 ? safe(Build.SUPPORTED_ABIS[0]) : "unknown";
        } catch (Throwable ignored) {
            return "unknown";
        }
    }

    private String appVersion() {
        try {
            return safe(context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0).versionName);
        } catch (Throwable ignored) {
            return "unknown";
        }
    }

    private static double round1(double value) {
        return Math.round(value * 10.0) / 10.0;
    }

    private static String safe(String value) {
        return value == null || value.trim().isEmpty() ? "unknown" : value.trim();
    }
}
