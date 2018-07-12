import UIKit
import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections
import Mapbox
import CarPlay

private typealias RouteRequestSuccess = (([Route]) -> Void)
private typealias RouteRequestFailure = ((NSError) -> Void)


class ViewController: UIViewController, MGLMapViewDelegate {
    
    // MARK: - IBOutlets
    @IBOutlet weak var longPressHintView: UIView!
    @IBOutlet weak var simulationButton: UIButton!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var bottomBar: UIView!
    @IBOutlet weak var clearMap: UIButton!
    @IBOutlet weak var bottomBarBackground: UIView!
    
    // MARK: Properties
    var mapView: NavigationMapView?
    var waypoints: [Waypoint] = [] {
        didSet {
            waypoints.forEach {
                $0.coordinateAccuracy = -1
            }
        }
    }

    var routes: [Route]? {
        didSet {
            startButton.isEnabled = (routes?.count ?? 0 > 0)
            guard let routes = routes,
                  let current = routes.first else { mapView?.removeRoutes(); return }

            mapView?.showRoutes(routes)
            mapView?.showWaypoints(current)
            
            guard #available(iOS 12.0, *), let carViewController = carViewController else { return }
                
            // Use custom extension on CPMaptemplate to make it easy to preview a `Route`.
            mapTemplate?.showTripPreviews(routes, textConfiguration: nil)
            
            
            carViewController.mapView?.showRoutes(routes)
            carViewController.mapView?.showWaypoints(current)
            
            // Wait for preview UI to show up so we can get the proper safeAreaInsets.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let padding: CGFloat = 25
                let bounds = UIEdgeInsets(top: carViewController.view.safeAreaInsets.top + padding,
                                          left: carViewController.view.safeAreaInsets.left + padding,
                                          bottom: carViewController.view.safeAreaInsets.bottom + padding,
                                          right: carViewController.view.safeAreaInsets.right + padding)
                
                let line = MGLPolyline(coordinates: current.coordinates!, count: UInt(current.coordinates!.count))
                carViewController.mapView?.setVisibleCoordinateBounds(line.overlayBounds, edgePadding: bounds, animated: true)
            }
        }
    }

    // MARK: Directions Request Handlers

    fileprivate lazy var defaultSuccess: RouteRequestSuccess = { [weak self] (routes) in
        guard let current = routes.first else { return }
        self?.mapView?.removeWaypoints()
        self?.routes = routes
        self?.waypoints = current.routeOptions.waypoints
        self?.clearMap.isHidden = false
        self?.longPressHintView.isHidden = true
    }

    fileprivate lazy var defaultFailure: RouteRequestFailure = { [weak self] (error) in
        self?.routes = nil //clear routes from the map
        print(error.localizedDescription)
    }

    var alertController: UIAlertController!
    
    // MARK: - CarPlay Properties
    
    var appViewFromCarPlayWindow: ViewController? {
        return ((appDelegate?.window?.rootViewController as? UINavigationController)?.viewControllers)?.first as? ViewController
    }
    
    var appDelegate: AppDelegate? {
        return UIApplication.shared.delegate as? AppDelegate
    }
    
    @available(iOS 12.0, *)
    var carViewController: ViewController? {
        return appDelegate?.carWindow?.rootViewController as? ViewController
    }
    
    @available(iOS 12.0, *)
    var interfaceController: CPInterfaceController? {
        return appDelegate?.interfaceController
    }
    
    @available(iOS 12.0, *)
    var mapTemplate: CPMapTemplate? {
        return interfaceController?.rootTemplate as? CPMapTemplate
    }

    // MARK: - Lifecycle Methods

    override func viewDidLoad() {
        super.viewDidLoad()

        CLLocationManager().requestWhenInUseAuthorization()
        
        alertController = UIAlertController(title: "Start Navigation", message: "Select the navigation type", preferredStyle: .actionSheet)
        
        typealias ActionHandler = (UIAlertAction) -> Void
        
        let basic: ActionHandler = {_ in self.startBasicNavigation() }
        let day: ActionHandler = {_ in self.startNavigation(styles: [DayStyle()]) }
        let night: ActionHandler = {_ in self.startNavigation(styles: [NightStyle()]) }
        let custom: ActionHandler = {_ in self.startCustomNavigation() }
        let styled: ActionHandler = {_ in self.startStyledNavigation() }
        
        let actionPayloads: [(String, UIAlertActionStyle, ActionHandler?)] = [
            ("Default UI", .default, basic),
            ("DayStyle UI", .default, day),
            ("NightStyle UI", .default, night),
            ("Custom UI", .default, custom),
            ("Styled UI", .default, styled),
            ("Cancel", .cancel, nil)
        ]
        
        actionPayloads
            .map { payload in UIAlertAction(title: payload.0, style: payload.1, handler: payload.2)}
            .forEach(alertController.addAction(_:))

        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = self.startButton
        }
        
        if #available(iOS 12.0, *) {
            buildCarPlayUI()
            mapTemplate?.mapDelegate = self
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        //Reload the mapView.
        setupMapView()

        // Reset the navigation styling to the defaults if we are returning from a presentation.
        if (presentedViewController != nil) {
            DayStyle().apply()
        }
    }

    // MARK: Gesture Recognizer Handlers

    @objc func didLongPress(tap: UILongPressGestureRecognizer) {
        guard let mapView = mapView, tap.state == .began else { return }

        if let annotation = mapView.annotations?.last, waypoints.count > 2 {
            mapView.removeAnnotation(annotation)
        }

        if waypoints.count > 1 {
            waypoints = Array(waypoints.suffix(1))
        }
        
        let coordinates = mapView.convert(tap.location(in: mapView), toCoordinateFrom: mapView)
        // Note: The destination name can be modified. The value is used in the top banner when arriving at a destination.
        let waypoint = Waypoint(coordinate: coordinates, name: "Dropped Pin #\(waypoints.endIndex + 1)")
        waypoints.append(waypoint)

        requestRoute()
    }


    // MARK: - IBActions
    @IBAction func replay(_ sender: Any) {
        let bundle = Bundle(for: ViewController.self)
        let filePath = bundle.path(forResource: "tunnel", ofType: "json")!
        let routeFilePath = bundle.path(forResource: "tunnel", ofType: "route")!
        let route = NSKeyedUnarchiver.unarchiveObject(withFile: routeFilePath) as! Route

        let locationManager = ReplayLocationManager(locations: Array<CLLocation>.locations(from: filePath))

        let navigationViewController = NavigationViewController(for: route, locationManager: locationManager)

        present(navigationViewController, animated: true, completion: nil)
    }

    @IBAction func simulateButtonPressed(_ sender: Any) {
        simulationButton.isSelected = !simulationButton.isSelected
    }

    @IBAction func clearMapPressed(_ sender: Any) {
        clearMap.isHidden = true
        mapView?.removeRoutes()
        mapView?.removeWaypoints()
        waypoints.removeAll()
        longPressHintView.isHidden = false
    }

    @IBAction func startButtonPressed(_ sender: Any) {
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - Public Methods
    // MARK: Route Requests
    func requestRoute() {
        guard waypoints.count > 0 else { return }
        guard let mapView = mapView else { return }

        let userWaypoint = Waypoint(location: mapView.userLocation!.location!, heading: mapView.userLocation?.heading, name: "User location")
        waypoints.insert(userWaypoint, at: 0)

        let options = NavigationRouteOptions(waypoints: waypoints)

        requestRoute(with: options, success: defaultSuccess, failure: defaultFailure)
    }

    fileprivate func requestRoute(with options: RouteOptions, success: @escaping RouteRequestSuccess, failure: RouteRequestFailure?) {

        let handler: Directions.RouteCompletionHandler = {(waypoints, potentialRoutes, potentialError) in
            if let error = potentialError, let fail = failure { return fail(error) }
            guard let routes = potentialRoutes else { return }
            return success(routes)
        }

        _ = Directions.shared.calculate(options, completionHandler: handler)
    }

    // MARK: Basic Navigation

    func startBasicNavigation() {
        guard let route = appViewFromCarPlayWindow?.routes?.first else { return }

        let navigationViewController = NavigationViewController(for: route, locationManager: navigationLocationManager())
        navigationViewController.delegate = self
        
        presentAndRemoveMapview(navigationViewController)
    }
    
    func startNavigation(styles: [Style]) {
        guard let route = routes?.first else { return }
        
        let navigationViewController = NavigationViewController(for: route, styles: styles, locationManager: navigationLocationManager())
        navigationViewController.delegate = self
        
        presentAndRemoveMapview(navigationViewController)
    }
    
    // MARK: Custom Navigation UI
    func startCustomNavigation() {
        guard let route = routes?.first else { return }

        guard let customViewController = storyboard?.instantiateViewController(withIdentifier: "custom") as? CustomViewController else { return }

        customViewController.userRoute = route

        let destination = MGLPointAnnotation()
        destination.coordinate = route.coordinates!.last!
        customViewController.destination = destination
        customViewController.simulateLocation = simulationButton.isSelected

        present(customViewController, animated: true, completion: nil)
    }

    // MARK: Styling the default UI

    func startStyledNavigation() {
        guard let route = routes?.first else { return }

        let styles = [CustomDayStyle(), CustomNightStyle()]

        let navigationViewController = NavigationViewController(for: route, styles: styles, locationManager: navigationLocationManager())
        navigationViewController.delegate = self

        presentAndRemoveMapview(navigationViewController)
    }

    func navigationLocationManager() -> NavigationLocationManager {
        guard let route = appViewFromCarPlayWindow?.routes?.first else { return NavigationLocationManager() }
        return simulationButton.isSelected ? SimulatedLocationManager(route: route) : NavigationLocationManager()
    }

    func presentAndRemoveMapview(_ navigationViewController: NavigationViewController) {
        let route = navigationViewController.routeController.routeProgress.route
        
        
        // If we have a CarPlay window, show navigation on it as well as on the phone.
        if #available(iOS 12.0, *), let carViewController = carViewController, let trip = route.asCPTrip, let mapTemplate = mapTemplate, let interfaceController = interfaceController {
            let session = mapTemplate.startNavigationSession(for: trip)
            
            mapTemplate.dismissPanningInterface(animated: true)
            
            mapTemplate.update(route.travelEstimates, for: trip, with: .default)
            mapTemplate.hideTripPreviews()
            let carPlayNavigationViewController = CarPlayNavigationViewController(for: navigationViewController.routeController, session: session, template: mapTemplate, interfaceController: interfaceController)
            carPlayNavigationViewController.carPlayNavigationDelegate = self
            carViewController.present(carPlayNavigationViewController, animated: true, completion: nil)
            
            if let appViewFromCarPlayWindow = appViewFromCarPlayWindow {
                navigationViewController.isUsedInConjunctionWithCarPlayWindow = true
                appViewFromCarPlayWindow.present(navigationViewController, animated: true)
            }
        } else {
            // If no CarPlay window, just start navigation on the phone.
            present(navigationViewController, animated: true) {
                self.mapView?.removeFromSuperview()
                self.mapView = nil
            }
        }
    }
    
    func setupMapView() {
        guard self.mapView == nil else { return }
        let mapView = NavigationMapView(frame: view.bounds)
        self.mapView = mapView
        
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.navigationMapDelegate = self
        mapView.userTrackingMode = .follow
        
        view.insertSubview(mapView, belowSubview: longPressHintView)
        
        let singleTap = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress(tap:)))
        mapView.gestureRecognizers?.filter({ $0 is UILongPressGestureRecognizer }).forEach(singleTap.require(toFail:))
        mapView.addGestureRecognizer(singleTap)
    }
    
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        self.mapView?.localizeLabels()
        
        if let routes = routes, let currentRoute = routes.first, let coords = currentRoute.coordinates {
            mapView.setVisibleCoordinateBounds(MGLPolygon(coordinates: coords, count: currentRoute.coordinateCount).overlayBounds, animated: false)
            self.mapView?.showRoutes(routes)
            self.mapView?.showWaypoints(currentRoute)
        }
        
        if #available(iOS 12.0, *) {
            buildCarPlayUI()
        }
    }
}

// MARK: - NavigationMapViewDelegate
extension ViewController: NavigationMapViewDelegate {
    func navigationMapView(_ mapView: NavigationMapView, didSelect waypoint: Waypoint) {
        guard let routeOptions = routes?.first?.routeOptions else { return }
        let modifiedOptions = routeOptions.without(waypoint: waypoint)

        presentWaypointRemovalActionSheet { _ in
            self.requestRoute(with:modifiedOptions, success: self.defaultSuccess, failure: self.defaultFailure)
        }
    }

    func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        guard let routes = routes else { return }
        guard let index = routes.index(where: { $0 == route }) else { return }
        self.routes!.remove(at: index)
        self.routes!.insert(route, at: 0)
    }

    private func presentWaypointRemovalActionSheet(completionHandler approve: @escaping ((UIAlertAction) -> Void)) {
        let title = NSLocalizedString("Remove Waypoint?", comment: "Waypoint Removal Action Sheet Title")
        let message = NSLocalizedString("Would you like to remove this waypoint?", comment: "Waypoint Removal Action Sheet Message")
        let removeTitle = NSLocalizedString("Remove Waypoint", comment: "Waypoint Removal Action Item Title")
        let cancelTitle = NSLocalizedString("Cancel", comment: "Waypoint Removal Action Sheet Cancel Item Title")

        let actionSheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        let remove = UIAlertAction(title: removeTitle, style: .destructive, handler: approve)
        let cancel = UIAlertAction(title: cancelTitle, style: .cancel, handler: nil)
        [remove, cancel].forEach(actionSheet.addAction(_:))

        self.present(actionSheet, animated: true, completion: nil)
    }
    
    // MARK: CarPlay Specific functions
    
    @available(iOS 12.0, *)
    func buildCarPlayUI() {
        guard let mapView = mapView, let mapTemplate = mapTemplate else { return }
        bottomBar.isHidden = true
        bottomBarBackground.isHidden = true
        longPressHintView.isHidden = true
        bottomBar.isHidden = true
        
        mapTemplate.mapDelegate = self
        mapTemplate.mapButtons = [CPMapButton.zoomInButton(for: mapView), CPMapButton.zoomOutButton(for: mapView)]
        mapTemplate.trailingNavigationBarButtons = [CPBarButton.panButton(for: mapView, mapTemplate: mapTemplate)]
    }
    
    func dismissAndCleanupUI() {
        appViewFromCarPlayWindow?.dismiss(animated: true, completion: nil)
        carViewController?.dismiss(animated: true, completion: nil)
        buildCarPlayUI()
        mapTemplate?.hideTripPreviews()
    }
}

// MARK: VoiceControllerDelegate methods
// To use these delegate methods, set the `VoiceControllerDelegate` on your `VoiceController`.
extension ViewController: VoiceControllerDelegate {
    // Called when there is an error with speaking a voice instruction.
    func voiceController(_ voiceController: RouteVoiceController, spokenInstructionsDidFailWith error: Error) {
        print(error.localizedDescription)
    }
    // Called when an instruction is interrupted by a new voice instruction.
    func voiceController(_ voiceController: RouteVoiceController, didInterrupt interruptedInstruction: SpokenInstruction, with interruptingInstruction: SpokenInstruction) {
        print(interruptedInstruction.text, interruptingInstruction.text)
    }
    
    func voiceController(_ voiceController: RouteVoiceController, willSpeak instruction: SpokenInstruction, routeProgress: RouteProgress) -> SpokenInstruction? {
        return SpokenInstruction(distanceAlongStep: instruction.distanceAlongStep, text: "New Instruction!", ssmlText: "<speak>New Instruction!</speak>")
    }
    
    // By default, the routeController will attempt to filter out bad locations.
    // If however you would like to filter these locations in,
    // you can conditionally return a Bool here according to your own heuristics.
    // See CLLocation.swift `isQualified` for what makes a location update unqualified.
    func navigationViewController(_ navigationViewController: NavigationViewController, shouldDiscard location: CLLocation) -> Bool {
        return true
    }
}

// MARK: WaypointConfirmationViewControllerDelegate
extension ViewController: WaypointConfirmationViewControllerDelegate {
    func confirmationControllerDidConfirm(_ confirmationController: WaypointConfirmationViewController) {
        confirmationController.dismiss(animated: true, completion: {
            guard let navigationViewController = self.presentedViewController as? NavigationViewController else { return }

            guard navigationViewController.routeController.routeProgress.route.legs.count > navigationViewController.routeController.routeProgress.legIndex + 1 else { return }
            navigationViewController.routeController.routeProgress.legIndex += 1
        })
    }
}

// MARK: NavigationViewControllerDelegate
extension ViewController: NavigationViewControllerDelegate {
    // By default, when the user arrives at a waypoint, the next leg starts immediately.
    // If you implement this method, return true to preserve this behavior.
    // Return false to remain on the current leg, for example to allow the user to provide input.
    // If you return false, you must manually advance to the next leg. See the example above in `confirmationControllerDidConfirm(_:)`.
    func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
        // When the user arrives, present a view controller that prompts the user to continue to their next destination
        // This type of screen could show information about a destination, pickup/dropoff confirmation, instructions upon arrival, etc.
        guard let confirmationController = self.storyboard?.instantiateViewController(withIdentifier: "waypointConfirmation") as? WaypointConfirmationViewController else { return true }

        confirmationController.delegate = self

        navigationViewController.present(confirmationController, animated: true, completion: nil)
        return false
    }
    
    // Called when the user hits the exit button.
    // If implemented, you are responsible for also dismissing the UI.
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        dismissAndCleanupUI()
    }
}

@available(iOS 12.0, *)
extension ViewController: CarPlayNavigationDelegate {
    func carPlaynavigationViewControllerDidDismiss(_ carPlayNavigationViewController: CarPlayNavigationViewController, byCanceling canceled: Bool) {
        dismissAndCleanupUI()
    }
}

// MARK: CPMapTemplateDelegate
@available(iOS 12.0, *)
extension ViewController: CPMapTemplateDelegate {
    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        startBasicNavigation()
    }
    
    func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        guard let routeIndex = trip.routeChoices.lastIndex(where: {$0 == routeChoice}), var routes = appViewFromCarPlayWindow?.routes else { return }
        let route = routes[routeIndex]
        guard let foundRoute = routes.firstIndex(where: {$0 == route}) else { return }
        routes.remove(at: foundRoute)
        routes.insert(route, at: 0)
        appViewFromCarPlayWindow?.routes = routes
    }
}

// Mark: VisualInstructionDelegate
extension ViewController: VisualInstructionDelegate {
    func label(_ label: InstructionLabel, willPresent instruction: VisualInstruction, as presented: NSAttributedString) -> NSAttributedString? {
        
        // Uncomment to mutate the instruction shown in the top instruction banner
        // let range = NSRange(location: 0, length: presented.length)
        // let mutable = NSMutableAttributedString(attributedString: presented)
        // mutable.mutableString.applyTransform(.latinToKatakana, reverse: false, range: range, updatedRange: nil)
        // return mutable
        
        return presented
    }
}
