//
//  CDVLocationServices.swift
//  CordovaLib
//
//  Created by Paul Michael Wisdom on 5/31/15.
//
//

import Foundation
import CoreLocation
import CoreMotion


let TAG = "[LocationServices]";
let PLUGIN_VERSION = "1.0";

func log(message: String){
    if(debug == true) {
        NSLog("%@ - %@", TAG, message)
    }
}

var locationManager = LocationManager();

//Option Vars
var distanceFilter = kCLDistanceFilterNone;
var desiredAccuracy = kCLLocationAccuracyBest;
var activityType = CLActivityType.other;
var interval = 5.0;
var debug: Bool?;
var useActivityDetection = false;
var aggressiveInterval = 2.0;

var stationaryTimout = (Double)(5 * 60); // 5 minutes

//State vars
var enabled = false;
var background = false;

var locationUpdateCallback:String?;
var locationCommandDelegate:CDVCommandDelegate?;

@objc(BackgroundLocationServices) open class BackgroundLocationServices : CDVPlugin {

    //Initialize things here (basically on run)
    override open func pluginInitialize() {
        super.pluginInitialize();

        locationManager.requestLocationPermissions();
        self.promptForNotificationPermission();

        NotificationCenter.default.addObserver(
            self,
            selector: Selector("onResume"),
            name: NSNotification.Name.UIApplicationWillEnterForeground,
            object: nil);

        NotificationCenter.default.addObserver(
            self,
            selector: Selector("onSuspend"),
            name: NSNotification.Name.UIApplicationDidEnterBackground,
            object: nil);

        NotificationCenter.default.addObserver(
            self,
            selector: Selector("willResign"),
            name: NSNotification.Name.UIApplicationWillResignActive,
            object: nil);
    }

    // 0 distanceFilter,
    // 1 desiredAccuracy,
    // 2 interval,
    // 3 fastestInterval -- (not used on ios),
    // 4 aggressiveInterval,
    // 5 debug,
    // 6 notificationTitle -- (not used on ios),
    // 7 notificationText-- (not used on ios),
    // 8 activityType, fences -- (not used ios)
    // 9 useActivityDetection
    open func configure(_ command: CDVInvokedUrlCommand) {

        //log(message: "configure arguments: \(command.arguments)");

        distanceFilter = command.argument(at: 0) as! CLLocationDistance;
        desiredAccuracy = self.toDesiredAccuracy(distance: (command.argument(at: 1) as! Int));
        interval = (Double)(command.argument(at: 2) as! Int / 1000); // Millseconds to seconds
        aggressiveInterval = (Double)(command.argument(at: 4) as! Int / 1000); // Millseconds to seconds
        activityType = self.toActivityType(type: command.argument(at: 8) as! String);
        debug = command.argument(at: 5) as? Bool;
        // Another way to save power is to set the pausesLocationUpdatesAutomatically property of your 
        // location manager object to true. Enabling this property lets the system reduce power consumption 
        // by disabling location hardware when the user is unlikely to be moving. Pausing updates does not 
        // diminish the quality of those updates, but can improve battery life significantly. To help the 
        // system determine when to pause updates, you must also assign an appropriate value to the activityType 
        // property of your location manager.


        useActivityDetection = command.argument(at: 9) as! Bool;

        log(message: "--------------------------------------------------------");
        log(message: "   Configuration Success");
        log(message: "       Distance Filter     \(distanceFilter)");
        log(message: "       Desired Accuracy    \(desiredAccuracy)");
        log(message: "       Activity Type       \(activityType)");
        log(message: "       Update Interval     \(interval)");
        log(message: "--------------------------------------------------------");

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId:command.callbackId)
    }

    open func registerForLocationUpdates(_ command: CDVInvokedUrlCommand) {
        log(message: "registerForLocationUpdates");
        locationUpdateCallback = command.callbackId;
        locationCommandDelegate = commandDelegate;
    }

    open func requestCurrentLocation(_ command: CDVInvokedUrlCommand) {
        log(message: "requestCurrentLocation");   

        locationManager.requestCurrentLocation();

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId:command.callbackId) 
    }

    open func start(_ command: CDVInvokedUrlCommand) {
        log(message: "Started");
        enabled = true;

        log(message: "Are we in the background? \(background)");

        locationManager.startUpdating();

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId:command.callbackId)
    }

    func stop(_ command: CDVInvokedUrlCommand) {
        log(message: "Stopped");
        enabled = false;

        locationManager.stopUpdating();

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate!.send(pluginResult, callbackId:command.callbackId)
    }

    func getVersion(_ command: CDVInvokedUrlCommand) {
        log(message: "Returning Version \(PLUGIN_VERSION)");

        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: PLUGIN_VERSION);
        commandDelegate!.send(pluginResult, callbackId: command.callbackId);
    }

    func promptForNotificationPermission() {
        log(message: "Prompting For Notification Permissions");
        if #available(iOS 8, *) {
            let settings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil);
            UIApplication.shared.registerUserNotificationSettings(settings)
        } else {
            UIApplication.shared.registerForRemoteNotifications(matching: [UIRemoteNotificationType.alert, UIRemoteNotificationType.sound, UIRemoteNotificationType.badge]);
        }
    }

    //State Methods
    func onResume() {
        log(message: "App Resumed");
        background = false;
    }

    func onSuspend() {
        log(message: "App Suspended. Enabled? \(enabled)");
        background = true;
    }

    func willResign() {
        log(message: "App Will Resign. Enabled? \(enabled)");
        background = true;
    }

    /* Pinpoint our location with the following accuracy:
     *
     *     kCLLocationAccuracyBestForNavigation  highest + sensor data
     *     kCLLocationAccuracyBest               highest
     *     kCLLocationAccuracyNearestTenMeters   10 meters
     *     kCLLocationAccuracyHundredMeters      100 meters
     *     kCLLocationAccuracyKilometer          1000 meters
     *     kCLLocationAccuracyThreeKilometers    3000 meters
     */

    func toDesiredAccuracy(distance: Int) -> CLLocationAccuracy {
        if(distance == 0) {
            return kCLLocationAccuracyBestForNavigation;
        } else if(distance < 10) {
            return kCLLocationAccuracyBest;
        } else if(distance < 100) {
            return kCLLocationAccuracyNearestTenMeters;
        } else if (distance < 1000) {
            return kCLLocationAccuracyHundredMeters
        } else if (distance < 3000) {
            return kCLLocationAccuracyKilometer;
        } else {
            return kCLLocationAccuracyThreeKilometers;
        }
    }

    func toActivityType(type: String) -> CLActivityType {
        if(type == "AutomotiveNavigation") {
            return CLActivityType.automotiveNavigation;
        } else if(type == "OtherNavigation") {
            return CLActivityType.otherNavigation;
        } else if(type == "Fitness") {
            return CLActivityType.fitness;
        } else {
            return CLActivityType.other;
        }
    }
}

class LocationManager : NSObject, CLLocationManagerDelegate {
    var manager = CLLocationManager();

    override init() {
        super.init();

        if(self.manager.delegate == nil) {
            log(message: "Setting location manager");
            self.manager.delegate = self;

            self.manager.desiredAccuracy = desiredAccuracy;
            self.manager.distanceFilter = distanceFilter;
            self.manager.pausesLocationUpdatesAutomatically = true;
            self.manager.activityType = activityType;
        }
    }

    func locationToDict(loc:CLLocation) -> NSDictionary {
        let locDict:Dictionary = [
            "latitude" : loc.coordinate.latitude,
            "longitude" : loc.coordinate.longitude,
            "accuracy" : loc.horizontalAccuracy,
            "timestamp" : ((loc.timestamp.timeIntervalSince1970 as Double) * 1000),
            "speed" : loc.speed,
            "altitude" : loc.altitude,
            "heading" : loc.course
        ]

        return locDict as NSDictionary;
    }

    func startUpdating() {
        self.manager.delegate = self;

        self.manager.startMonitoringSignificantLocationChanges();

        log(message: "Starting Location Updates!");
    }

    func stopUpdating() {
        log(message: "[LocationManager.stopUpdating] Stopping Location Updates!");
        self.manager.stopMonitoringSignificantLocationChanges();
    }

    func requestCurrentLocation() {
        self.manager.requestLocation();
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]){
        let lastLocation = locations.last!;

        let latitude = lastLocation.coordinate.latitude;
        let longitude = lastLocation.coordinate.longitude;
        let accuracy = lastLocation.horizontalAccuracy;
        var msg = "Got Location Update:  { \(latitude) - \(longitude) }  Accuracy: \(accuracy)";

        log(message: msg);
        NotificationManager.manager.notify(text: msg);

        locationCommandDelegate?.run(inBackground: {
             var result:CDVPluginResult?;
            let loc = self.locationToDict(loc: lastLocation) as [NSObject: AnyObject];

                result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs:loc);
                result!.setKeepCallbackAs(true);
                locationCommandDelegate?.send(result, callbackId:locationUpdateCallback);
        });
    }

    private func locationManagerDidPauseLocationUpdates(manager: CLLocationManager) {
        log(message: "Location Manager Paused Location Updates");
    }

    private func locationManagerDidResumeLocationUpdates(manager: CLLocationManager) {
        log(message: "Location Manager Resumed Location Updates");
    }

    private func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        log(message: "LOCATION ERROR: \(error.description)");

        locationCommandDelegate?.run(inBackground: {

            var result:CDVPluginResult?;

            result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: error.description);
            result!.setKeepCallbackAs(true);
            locationCommandDelegate?.send(result, callbackId:locationUpdateCallback);
        });


    }
    private func locationManager(manager: CLLocationManager, didFinishDeferredUpdatesWithError error: NSError?) {
        log(message: "Location Manager FAILED deferred \(error!.description)");
    }

    func requestLocationPermissions() {
        if (!CLLocationManager.locationServicesEnabled()) {
            log(message: "Location services is not enabled");
        } else {
            log(message: "Location services enabled");
        }
        if (!CLLocationManager.significantLocationChangeMonitoringAvailable()) {
            log(message: "Significant location change monitoring is not available");
        }
        else {
            log(message: "Significant location change monitoring is available");
        }
        if #available(iOS 8, *) {
            self.manager.requestAlwaysAuthorization();
        }
    }
}

class NotificationManager : NSObject {

    static var manager = NotificationManager();

    func notify(text: String) {
        if(debug == true) {
            log(message: "Sending Notification");
            let notification = UILocalNotification();
            notification.timeZone = TimeZone.current;
            notification.soundName = UILocalNotificationDefaultSoundName;
            notification.alertBody = text;

            UIApplication.shared.scheduleLocalNotification(notification);
        }
    }
}
