package com.boostyourapp.cordova;

import com.boostyourapp.network.BoostEvent;
import com.boostyourapp.network.BoostNetwork;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Pont Cordova : transmet les appels au cœur Android du SDK, sans logique propre. */
public class BoostNetworkPlugin extends CordovaPlugin {

    private CallbackContext eventCallback;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        switch (action) {
            case "initialize": {
                String appKey = args.optString(0, "").trim();
                if (appKey.isEmpty()) {
                    callbackContext.error("appKey manquante");
                    return true;
                }
                // L'activité de Cordova est déjà affichée : le SDK s'y attache directement
                BoostNetwork.init(cordova.getActivity(), appKey);
                callbackContext.success();
                return true;
            }
            case "showBanner":
                BoostNetwork.showBanner(args.optString(0, "bottom"));
                callbackContext.success();
                return true;
            case "setStyle":
                BoostNetwork.setStyle(args.optString(0, "standard"), args.isNull(1) ? null : args.optString(1));
                callbackContext.success();
                return true;
            case "loadInterstitial":
                BoostNetwork.loadInterstitial();
                callbackContext.success();
                return true;
            case "isInterstitialReady":
                callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, BoostNetwork.isInterstitialReady()));
                return true;
            case "showInterstitial":
                // Résolu à la fermeture (true), ou aussitôt s'il n'y en a pas de prêt (false)
                BoostNetwork.showInterstitial(shown ->
                    callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, shown)));
                return true;
            case "hideBanner":
                BoostNetwork.hideBanner();
                callbackContext.success();
                return true;
            case "setEndpoint":
                BoostNetwork.setEndpoint(args.getString(0), args.getString(1));
                callbackContext.success();
                return true;
            case "onEvent": {
                eventCallback = callbackContext;
                BoostNetwork.onEvent(this::sendEvent);
                PluginResult result = new PluginResult(PluginResult.Status.NO_RESULT);
                result.setKeepCallback(true);
                callbackContext.sendPluginResult(result);
                return true;
            }
            default:
                return false;
        }
    }

    /** Même forme que sur iOS : { type, adId } ou { type, code, message } */
    private void sendEvent(BoostEvent event) {
        CallbackContext callback = eventCallback;
        if (callback == null) return;
        JSONObject data = new JSONObject();
        try {
            data.put("type", event.getType());
            if (event.getAdIdOrNull() != null) {
                data.put("adId", event.getAdIdOrNull());
            }
            if (event instanceof BoostEvent.Error) {
                data.put("code", ((BoostEvent.Error) event).getCode());
                data.put("message", ((BoostEvent.Error) event).getMessage());
            }
        } catch (JSONException e) {
            return;
        }
        PluginResult result = new PluginResult(PluginResult.Status.OK, data);
        result.setKeepCallback(true);
        callback.sendPluginResult(result);
    }

    @Override
    public void onDestroy() {
        BoostNetwork.onEvent(null);
        eventCallback = null;
    }
}
