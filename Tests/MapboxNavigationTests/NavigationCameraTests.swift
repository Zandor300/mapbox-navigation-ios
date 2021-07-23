import XCTest
import Turf
import MapboxMaps
import MapboxDirections

@testable import TestHelper
@testable import MapboxNavigation
@testable import MapboxCoreNavigation

class ViewportDataSourceMock: ViewportDataSource {
    
    public weak var delegate: ViewportDataSourceDelegate?
    
    public var followingMobileCamera: CameraOptions = CameraOptions()
    
    public var followingCarPlayCamera: CameraOptions = CameraOptions()
    
    public var overviewMobileCamera: CameraOptions = CameraOptions()
    
    public var overviewCarPlayCamera: CameraOptions = CameraOptions()
    
    weak var mapView: MapView?
    
    public required init(_ mapView: MapView) {
        self.mapView = mapView
    }
    
    func update(to cameraOptions: CameraOptions) {
        followingMobileCamera = cameraOptions
        followingCarPlayCamera = cameraOptions
        overviewMobileCamera = cameraOptions
        overviewCarPlayCamera = cameraOptions
    }
}

class CameraStateTransitionMock: CameraStateTransition {
    
    weak var mapView: MapView?
    
    let transitionDuration = 0.1
    
    required init(_ mapView: MapView) {
        self.mapView = mapView
    }
    
    func transitionToFollowing(_ cameraOptions: CameraOptions, completion: @escaping (() -> Void)) {
        // Delay is used to be able to verify whether `NavigationCameraState` changes from
        // `NavigationCameraState.transitionToFollowing` to `NavigationCameraState.following`.
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
            completion()
        }
    }
    
    func transitionToOverview(_ cameraOptions: CameraOptions, completion: @escaping (() -> Void)) {
        // Delay is used to be able to verify whether `NavigationCameraState` changes from
        // `NavigationCameraState.transitionToOverview` to `NavigationCameraState.overview`.
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
            completion()
        }
    }
    
    func update(to cameraOptions: CameraOptions, state: NavigationCameraState) {
        // No-op
    }
    
    func cancelPendingTransition() {
        // No-op
    }
}

class ViewportDataSourceDelegateMock: ViewportDataSourceDelegate {
    
    var cameraOptions: [String: CameraOptions]? = nil
    
    func viewportDataSource(_ dataSource: ViewportDataSource, didUpdate cameraOptions: [String: CameraOptions]) {
        self.cameraOptions = cameraOptions
    }
}

class LocationProviderMock: LocationProvider {
    
    var locationProviderOptions: LocationOptions
    
    var authorizationStatus: CLAuthorizationStatus
    
    var accuracyAuthorization: CLAccuracyAuthorization
    
    var headingOrientation: CLDeviceOrientation
    
    var heading: CLHeading?
    
    weak var delegate: LocationProviderDelegate?
    
    init() {
        locationProviderOptions = LocationOptions()
        authorizationStatus = .denied
        accuracyAuthorization = .reducedAccuracy
        headingOrientation = .unknown
    }
    
    func setDelegate(_ delegate: LocationProviderDelegate) {
        self.delegate = delegate
    }
    
    func requestAlwaysAuthorization() {
        // No-op
    }
    
    func requestWhenInUseAuthorization() {
        // No-op
    }
    
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) {
        // No-op
    }
    
    func startUpdatingLocation() {
        // No-op
    }
    
    func stopUpdatingLocation() {
        // No-op
    }
    
    func startUpdatingHeading() {
        // No-op
    }
    
    func stopUpdatingHeading() {
        // No-op
    }
    
    func dismissHeadingCalibrationDisplay() {
        // No-op
    }
}

extension LocationProviderMock: LocationProviderDelegate {
    
    func locationProvider(_ provider: LocationProvider, didUpdateLocations locations: [CLLocation]) {
        delegate?.locationProvider(provider, didUpdateLocations: locations)
    }
    
    func locationProvider(_ provider: LocationProvider, didUpdateHeading newHeading: CLHeading) {
        // No-op
    }
    
    func locationProvider(_ provider: LocationProvider, didFailWithError error: Error) {
        // No-op
    }
    
    func locationProviderDidChangeAuthorization(_ provider: LocationProvider) {
        // No-op
    }
}

class NavigationCameraTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testNavigationMapViewCameraType() {
        var navigationMapView = NavigationMapView(frame: .zero)
        XCTAssertEqual(navigationMapView.navigationCamera.type, .mobile)
        
        navigationMapView = NavigationMapView(frame: .zero, navigationCameraType: .carPlay)
        XCTAssertEqual(navigationMapView.navigationCamera.type, .carPlay)
    }
    
    func testNavigationCameraDefaultState() {
        // By default Navigation Camera moves to `NavigationCameraState.following` state.
        let navigationMapView = NavigationMapView(frame: .zero)
        XCTAssertEqual(navigationMapView.navigationCamera.state, .following)
        
        let route = Fixture.route(from: jsonFileName,
                                  options: routeOptions)
        
        let navigationViewController = NavigationViewController(for: route,
                                                                routeIndex: 0,
                                                                routeOptions: routeOptions)
        
        XCTAssertEqual(navigationViewController.navigationMapView?.navigationCamera.state, .following)
    }
    
    func testNavigationCameraFollowingState() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        navigationMapView.navigationCamera.cameraStateTransition = CameraStateTransitionMock(navigationMapView.mapView)
        
        // By default Navigation Camera moves to `NavigationCameraState.following` state.
        XCTAssertEqual(navigationMapView.navigationCamera.state, .following)
        
        let overviewExpectation = expectation(description: "Overview camera expectation.")
        
        // After calling `NavigationCamera.moveToOverview()` camera state should be set
        // to `NavigationCameraState.transitionToOverview` first, only after finishing transition
        // to `NavigationCameraState.overview`.
        navigationMapView.navigationCamera.moveToOverview {
            overviewExpectation.fulfill()
        }
        XCTAssertEqual(navigationMapView.navigationCamera.state, .transitionToOverview)
        
        wait(for: [overviewExpectation], timeout: 1.0)
        
        // At the end of transition it is expected that camera state is `NavigationCameraState.overview`.
        XCTAssertEqual(navigationMapView.navigationCamera.state, .overview)
        
        let followingExpectation = expectation(description: "Following camera expectation.")
        
        // After calling `NavigationCamera.follow()` camera state should be set
        // to `NavigationCameraState.transitionToFollowing` first, only after finishing transition
        // to `NavigationCameraState.following`.
        navigationMapView.navigationCamera.follow {
            followingExpectation.fulfill()
        }
        XCTAssertEqual(navigationMapView.navigationCamera.state, .transitionToFollowing)
        
        wait(for: [followingExpectation], timeout: 1.0)
        
        XCTAssertEqual(navigationMapView.navigationCamera.state, .following)
    }
    
    func testNavigationCameraOverviewStateDoesntChange() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        navigationMapView.navigationCamera.cameraStateTransition = CameraStateTransitionMock(navigationMapView.mapView)
        
        // By default Navigation Camera moves to `NavigationCameraState.following` state.
        XCTAssertEqual(navigationMapView.navigationCamera.state, .following)
        
        let overviewExpectation = expectation(description: "Overview camera expectation.")
        
        // After calling `NavigationCamera.moveToOverview()` camera state should be set
        // to `NavigationCameraState.transitionToOverview` first, only after finishing transition
        // to `NavigationCameraState.overview`.
        navigationMapView.navigationCamera.moveToOverview {
            overviewExpectation.fulfill()
        }
        XCTAssertEqual(navigationMapView.navigationCamera.state, .transitionToOverview)
        
        wait(for: [overviewExpectation], timeout: 1.0)
        
        // At the end of transition it is expected that camera state is `NavigationCameraState.overview`.
        XCTAssertEqual(navigationMapView.navigationCamera.state, .overview)
        
        // All further calls to `NavigationCamera.moveToOverview()` should not change camera state and
        // will be executed right away.
        navigationMapView.navigationCamera.moveToOverview {
            XCTAssertEqual(navigationMapView.navigationCamera.state, .overview)
        }
    }
    
    func testCustomViewportDataSource() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        let viewportDataSourceMock = ViewportDataSourceMock(navigationMapView.mapView)
        XCTAssertEqual(viewportDataSourceMock.mapView, navigationMapView.mapView, "MapView instances should be equal.")
        
        // It should be possible to override default `ViewportDataSource` implementation and provide
        // own data provider.
        navigationMapView.navigationCamera.viewportDataSource = viewportDataSourceMock
        XCTAssertTrue(navigationMapView.navigationCamera.viewportDataSource is ViewportDataSourceMock, "ViewportDataSource should have correct type.")
        
        let cameraOptions = CameraOptions(center: CLLocationCoordinate2D(latitude: 37.788443,
                                                                         longitude: -122.4020258),
                                          padding: .zero,
                                          anchor: .zero,
                                          zoom: 15.0,
                                          bearing: 0.0,
                                          pitch: 45.0)
        
        viewportDataSourceMock.update(to: cameraOptions)
        
        XCTAssertEqual(viewportDataSourceMock.followingMobileCamera, cameraOptions, "CameraOptions should be equal.")
    }
    
    func testNavigationCameraIdleState() {
        // By default Navigation Camera moves to `NavigationCameraState.following` state.
        let navigationMapView = NavigationMapView(frame: .zero)
        XCTAssertEqual(navigationMapView.navigationCamera.state, .following)
        
        // After calling `NavigationCamera.stop()` camera state should be set to
        // `NavigationCameraState.idle`.
        navigationMapView.navigationCamera.stop()
        XCTAssertEqual(navigationMapView.navigationCamera.state, .idle)
        
        // All further calls to `NavigationCamera.stop()` should not change camera state.
        navigationMapView.navigationCamera.stop()
        XCTAssertEqual(navigationMapView.navigationCamera.state, .idle)
    }
    
    func testViewportDataSourceDelegateForFreeDrive() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        // By default `NavigationViewportDataSource` listens to `Notification.Name.passiveLocationManagerDidUpdate`.
        let navigationViewportDataSource = navigationMapView.navigationCamera.viewportDataSource as? NavigationViewportDataSource
        
        let viewportDataSourceDelegateMock = ViewportDataSourceDelegateMock()
        navigationViewportDataSource?.delegate = viewportDataSourceDelegateMock
        
        let expectation = self.expectation(forNotification: .passiveLocationManagerDidUpdate,
                                           object: self) { _ in
            return true
        }
        
        let location = CLLocation(latitude: 37.112341, longitude: -122.1111678)
        let rawLocation = CLLocation(latitude: 37.788443, longitude: -122.4020258)
        
        // Send `Notification.Name.passiveLocationManagerDidUpdate` notification and make sure that
        // `CameraOptions`, which were generated by `NavigationViewportDataSource` are correct.
        sendPassiveLocationManagerDidUpdate(location, rawLocation: rawLocation)
        
        wait(for: [expectation], timeout: 1.0)
        
        // It is expected that `NavigationViewportDataSource` uses default values for `CameraOptions`
        // during free-drive. Location, snapped to the road network should be used instead of raw one.
        let expectedAltitude = 4000.0
        let expectedZoomLevel = CGFloat(ZoomLevelForAltitude(expectedAltitude,
                                                             navigationMapView.mapView.cameraState.pitch,
                                                             location.coordinate.latitude,
                                                             navigationMapView.mapView.bounds.size))
        
        let expectedCameraOptions = CameraOptions(center: location.coordinate,
                                                  padding: .zero,
                                                  anchor: .zero,
                                                  zoom: expectedZoomLevel,
                                                  bearing: 0.0,
                                                  pitch: 0.0)
        
        let followingMobileCameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingMobileCamera]
        verifyCameraOptionsAreEqual(followingMobileCameraOptions, expectedCameraOptions: expectedCameraOptions)
        
        let followingCarPlayCameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingCarPlayCamera]
        verifyCameraOptionsAreEqual(followingCarPlayCameraOptions, expectedCameraOptions: expectedCameraOptions)
        
        // In `NavigationCameraState.overview` state during free-drive navigation all properties of
        // `CameraOptions` should be `nil`.
        let overviewMobileCameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.overviewMobileCamera]
        verifyCameraOptionsAreNil(overviewMobileCameraOptions)
        
        let overviewCarPlayCameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.overviewCarPlayCamera]
        verifyCameraOptionsAreNil(overviewCarPlayCameraOptions)
    }
    
    func testViewportDataSourceDelegateForActiveGuidance() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        // Create new `NavigationViewportDataSource` instance, which listens to the
        // `Notification.Name.routeControllerProgressDidChange` notification, which is sent during
        // active guidance navigation.
        let navigationViewportDataSource = NavigationViewportDataSource(navigationMapView.mapView,
                                                                        viewportDataSourceType: .active)
        
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        let viewportDataSourceDelegateMock = ViewportDataSourceDelegateMock()
        navigationMapView.navigationCamera.viewportDataSource.delegate = viewportDataSourceDelegateMock
        
        guard let route = self.route(from: "route-for-navigation-camera") else {
            XCTFail("Route should be valid.")
            return
        }
        
        let routeProgress = RouteProgress(route: route,
                                          routeIndex: 0,
                                          options: NavigationRouteOptions(coordinates: []))
        
        // Since second `stepIndex` is right after sharp maneuver default navigation camera behavior
        // will change `CameraOptions.pitch` to `FollowingCameraOptions.defaultPitch`.
        routeProgress.currentLegProgress.stepIndex = 1
        
        let expectation = self.expectation(forNotification: .routeControllerProgressDidChange,
                                           object: self) { _ in
            return true
        }
        
        let location = CLLocation(latitude: 37.765469, longitude: -122.415279)
        
        sendRouteControllerProgressDidChangeNotification(routeProgress, location: location)
        
        wait(for: [expectation], timeout: 1.0)
        
        guard let temporaryPitch = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingMobileCamera]?.pitch else {
            XCTFail("Pitch should be valid.")
            return
        }
        
        let pitch = Double(temporaryPitch)
        XCTAssertEqual(pitch,
                       navigationViewportDataSource.options.followingCameraOptions.defaultPitch,
                       "Pitches should be equal.")
    }
    
    func testViewportDataSourceDelegateForLocationProvider() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        let locationProviderMock = LocationProviderMock()
        navigationMapView.mapView.location.overrideLocationProvider(with: locationProviderMock)
        
        // Create `NavigationViewportDataSource` instance, which listens to the raw locations updates.
        let navigationViewportDataSource = NavigationViewportDataSource(navigationMapView.mapView,
                                                                        viewportDataSourceType: .raw)
        
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        let viewportDataSourceDelegateMock = ViewportDataSourceDelegateMock()
        navigationMapView.navigationCamera.viewportDataSource.delegate = viewportDataSourceDelegateMock
        
        let didUpdateCameraOptionsExpectation = self.expectation {
            return viewportDataSourceDelegateMock.cameraOptions != nil
        }
        
        let location = CLLocation(latitude: 0.0, longitude: 0.0)
        locationProviderMock.locationProvider(locationProviderMock, didUpdateLocations: [location])
        
        wait(for: [didUpdateCameraOptionsExpectation], timeout: 5.0)
        
        // It is expected that `NavigationViewportDataSource` uses default values for `CameraOptions`
        // in case if raw locations are consumed.
        let expectedAltitude = 4000.0
        let expectedZoomLevel = CGFloat(ZoomLevelForAltitude(expectedAltitude,
                                                             navigationMapView.mapView.cameraState.pitch,
                                                             location.coordinate.latitude,
                                                             navigationMapView.mapView.bounds.size))
        
        let expectedCameraOptions = CameraOptions(center: location.coordinate,
                                                  padding: .zero,
                                                  anchor: .zero,
                                                  zoom: expectedZoomLevel,
                                                  bearing: 0.0,
                                                  pitch: 0.0)
        
        let followingMobileCameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingMobileCamera]
        verifyCameraOptionsAreEqual(followingMobileCameraOptions, expectedCameraOptions: expectedCameraOptions)
        
        let followingCarPlayCameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingCarPlayCamera]
        verifyCameraOptionsAreEqual(followingCarPlayCameraOptions, expectedCameraOptions: expectedCameraOptions)
    }
    
    func testFollowingCameraOptions() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        // Create new `NavigationViewportDataSource` instance, which listens to the
        // `Notification.Name.routeControllerProgressDidChange` notification, which is sent during
        // active guidance navigation.
        let navigationViewportDataSource = NavigationViewportDataSource(navigationMapView.mapView,
                                                                        viewportDataSourceType: .active)
        
        // Prevent any camera related modifications, which could be done by `NavigationViewportDataSource`.
        navigationViewportDataSource.options.followingCameraOptions.centerUpdatesAllowed = false
        navigationViewportDataSource.options.followingCameraOptions.zoomUpdatesAllowed = false
        navigationViewportDataSource.options.followingCameraOptions.bearingUpdatesAllowed = false
        navigationViewportDataSource.options.followingCameraOptions.pitchUpdatesAllowed = false
        navigationViewportDataSource.options.followingCameraOptions.paddingUpdatesAllowed = false
        
        let expectedCenterCoordinate = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        navigationViewportDataSource.followingMobileCamera.center = expectedCenterCoordinate
        
        let expectedZoom: CGFloat = 11.1
        navigationViewportDataSource.followingMobileCamera.zoom = expectedZoom
        
        let expectedBearing = 22.2
        navigationViewportDataSource.followingMobileCamera.bearing = expectedBearing
        
        let expectedPitch: CGFloat = 33.3
        navigationViewportDataSource.followingMobileCamera.pitch = expectedPitch
        
        let expectedPadding = UIEdgeInsets(top: 1.0, left: 2.0, bottom: 3.0, right: 4.0)
        navigationViewportDataSource.followingMobileCamera.padding = expectedPadding
        
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        let viewportDataSourceDelegateMock = ViewportDataSourceDelegateMock()
        navigationMapView.navigationCamera.viewportDataSource.delegate = viewportDataSourceDelegateMock
        
        guard let route = self.route(from: "route-for-navigation-camera") else {
            XCTFail("Route should be valid.")
            return
        }
        
        let routeProgress = RouteProgress(route: route,
                                          routeIndex: 0,
                                          options: NavigationRouteOptions(coordinates: []))
        
        // Change `stepIndex` to simulate `CameraOptions` change. Since update to all `CameraOptions`
        // parameters is not allowed, this change will have no effect.
        routeProgress.currentLegProgress.stepIndex = 1
        
        let expectation = self.expectation(forNotification: .routeControllerProgressDidChange,
                                           object: self) { _ in
            return true
        }
        
        let location = CLLocation(latitude: 37.765469, longitude: -122.415279)
        
        sendRouteControllerProgressDidChangeNotification(routeProgress, location: location)
        
        wait(for: [expectation], timeout: 1.0)
        
        let cameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingMobileCamera]
        
        XCTAssertEqual(cameraOptions?.center, expectedCenterCoordinate, "Center coordinates should be equal.")
        XCTAssertEqual(cameraOptions?.zoom, expectedZoom, "Zooms should be equal.")
        XCTAssertEqual(cameraOptions?.bearing, expectedBearing, "Bearings should be equal.")
        XCTAssertEqual(cameraOptions?.pitch, expectedPitch, "Pitches should be equal.")
        XCTAssertEqual(cameraOptions?.padding, expectedPadding, "Paddings should be equal.")
    }
    
    func testBearingSmoothingIsDisabled() {
        let navigationMapView = NavigationMapView(frame: .zero)
        
        // Create new `NavigationViewportDataSource` instance, which listens to the
        // `Notification.Name.routeControllerProgressDidChange` notification, which is sent during
        // active guidance navigation.
        let navigationViewportDataSource = NavigationViewportDataSource(navigationMapView.mapView,
                                                                        viewportDataSourceType: .active)
        
        // Make sure that bearing smoothing is enabled by default.
        XCTAssertTrue(navigationViewportDataSource.options.followingCameraOptions.bearingSmoothing.enabled, "Bearing smoothing should be enabled by default.")
        
        navigationViewportDataSource.options.followingCameraOptions.bearingSmoothing.enabled = false
        
        navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
        
        let viewportDataSourceDelegateMock = ViewportDataSourceDelegateMock()
        navigationMapView.navigationCamera.viewportDataSource.delegate = viewportDataSourceDelegateMock
        
        guard let route = self.route(from: "route-for-navigation-camera-bearing-smoothing") else {
            XCTFail("Route should be valid.")
            return
        }
        
        let routeProgress = RouteProgress(route: route,
                                          routeIndex: 0,
                                          options: NavigationRouteOptions(coordinates: []))
        
        let expectation = self.expectation(forNotification: .routeControllerProgressDidChange,
                                           object: self) { _ in
            return true
        }
        
        // Since bearing smoothing is disabled it is expected that `CameraOptions.bearing`, which was
        // returned from the `ViewportDataSourceDelegateMock` will be `123.0`.
        let expectedBearing = 123.0
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.769595, longitude: -122.442412),
                                  altitude: 0.0,
                                  horizontalAccuracy: 0.0,
                                  verticalAccuracy: 0.0,
                                  course: expectedBearing,
                                  speed: 0.0,
                                  timestamp: Date())
        
        sendRouteControllerProgressDidChangeNotification(routeProgress, location: location)
        
        wait(for: [expectation], timeout: 1.0)
        
        let cameraOptions = viewportDataSourceDelegateMock.cameraOptions?[CameraOptions.followingMobileCamera]
        XCTAssertEqual(cameraOptions?.bearing, expectedBearing, "Bearings should be equal.")
    }
    
    // MARK: - Helper methods
    
    func route(from file: String) -> Route? {
        // Load previously serialized `Route` object in JSON format and deserialize it.
        let routeData = Fixture.JSONFromFileNamed(name: file)
        let decoder = JSONDecoder()
        decoder.userInfo[.options] = routeOptions
        
        guard let route = try? decoder.decode(Route.self, from: routeData) else {
            return nil
        }
        
        return route
    }
    
    func sendPassiveLocationManagerDidUpdate(_ location: CLLocation, rawLocation: CLLocation) {
        let userInfo: [PassiveLocationManager.NotificationUserInfoKey: Any] = [
            .locationKey: location,
            .rawLocationKey: rawLocation
        ]
        
        NotificationCenter.default.post(name: .passiveLocationManagerDidUpdate,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func sendRouteControllerProgressDidChangeNotification(_ routeProgress: RouteProgress,
                                                          location: CLLocation) {
        let userInfo: [RouteController.NotificationUserInfoKey: Any] = [
            .routeProgressKey: routeProgress,
            .locationKey: location,
        ]
        
        NotificationCenter.default.post(name: .routeControllerProgressDidChange,
                                        object: self,
                                        userInfo: userInfo)
    }
    
    func verifyCameraOptionsAreEqual(_ givenCameraOptions: CameraOptions?, expectedCameraOptions: CameraOptions?) {
        XCTAssertEqual(givenCameraOptions?.center, expectedCameraOptions?.center, "Center coordinates should be equal.")
        XCTAssertEqual(givenCameraOptions?.anchor, expectedCameraOptions?.anchor, "Anchors should be equal.")
        XCTAssertEqual(givenCameraOptions?.padding, expectedCameraOptions?.padding, "Paddings should be equal.")
        XCTAssertEqual(givenCameraOptions?.bearing, expectedCameraOptions?.bearing, "Bearings should be equal.")
        XCTAssertEqual(givenCameraOptions?.zoom, expectedCameraOptions?.zoom, "Zooms should be equal.")
        XCTAssertEqual(givenCameraOptions?.pitch, expectedCameraOptions?.pitch, "Pitches should be equal.")
    }
    
    func verifyCameraOptionsAreNil(_ cameraOptions: CameraOptions?) {
        XCTAssertNil(cameraOptions?.center, "Center should be nil.")
        XCTAssertNil(cameraOptions?.anchor, "Anchor should be nil.")
        XCTAssertNil(cameraOptions?.padding, "Padding should be nil.")
        XCTAssertNil(cameraOptions?.bearing, "Bearing should be nil.")
        XCTAssertNil(cameraOptions?.zoom, "Zoom should be nil.")
        XCTAssertNil(cameraOptions?.pitch, "Pitch should be nil.")
    }
}