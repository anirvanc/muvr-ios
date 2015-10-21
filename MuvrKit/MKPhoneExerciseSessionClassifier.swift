import Foundation

///
/// Provides a way to load a model given its identifier. Implementations should not only
/// load the underlying model, but should also consider other model & user-specific settings.
///
public protocol MKExerciseModelSource {
    
    ///
    /// Gets the exercise model for the given ``id``.
    ///
    /// - parameter id: the exercise model id to load
    ///
    func getExerciseModel(id id: MKExerciseModelId) -> MKExerciseModel
    
}

///
/// Implementation of the two connectivity delegates that can classify the incoming data
///
public final class MKSessionClassifier : MKExerciseConnectivitySessionDelegate, MKSensorDataConnectivityDelegate {
    private let exerciseModelSource: MKExerciseModelSource
    
    /// all sessions
    private(set) public var sessions: [MKExerciseSession] = []
    
    /// the classification result delegate
    public var delegate: MKSessionClassifierDelegate? = nil    // Remember to call the delegate methods on ``dispatch_get_main_queue()``
    
    /// the queue for immediate classification, with high-priority QoS
    private let classificationQueue: dispatch_queue_t = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
    /// the queue for summary & reclassification, if needed, with background QoS
    private let summaryQueue: dispatch_queue_t = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)

    ///
    /// Initializes this instance of the session classifier, supplying a list of so-far unclassified
    /// sessions. These will be classified with the device's best effort, keeping the as-it-happens
    /// classification as a priority
    ///
    /// - parameter exerciseModelSource: implementation of the ``MKExerciseModelSource`` protocol
    /// - parameter unclassified: the list of not-yet-classified connectivity sessions
    ///
    public init(exerciseModelSource: MKExerciseModelSource) {
        self.exerciseModelSource = exerciseModelSource
    }
    
    private func classify(exerciseModelId exerciseModelId: MKExerciseModelId, sensorData: MKSensorData) -> [MKClassifiedExercise]? {
        let model = exerciseModelSource.getExerciseModel(id: exerciseModelId)
        let classifier = MKClassifier(model: model)
        return try? classifier.classify(block: sensorData, maxResults: 10)
    }
    
    ///
    /// Summarises the entire session. It reclassifies all exercises and may do some magic in the
    /// future. Remember to call this function on the ``summaryQueue``.
    ///
    /// - parameter session: the connectivity session to summarize
    /// - returns: the summarized session, if possible
    ///
    private func summarise(session session: MKExerciseConnectivitySession) -> MKExerciseSession? {
        if let sensorData = session.sensorData {
            var exerciseSession = MKExerciseSession()
            exerciseSession.sensorData = sensorData
            if let classified = classify(exerciseModelId: session.exerciseModelId, sensorData: sensorData) {
                exerciseSession.classifiedExercises.appendContentsOf(classified)
            }
            return exerciseSession
        }
        
        return nil
    }
    
    public func exerciseConnectivitySessionDidEnd(session session: MKExerciseConnectivitySession) {
        // TODO: Improve me? The ``session`` is the whole thing, presumably, we can just add instead of needing the last element
        if sessions.count == 0 { return }
        
        if let delegate = self.delegate {
            dispatch_async(dispatch_get_main_queue()) { delegate.sessionClassifierDidEnd(self.sessions.last!) }
        }

        dispatch_async(summaryQueue) {
            if let exerciseSession = self.summarise(session: session) {
                self.sessions[self.sessions.count - 1] = exerciseSession
                if let delegate = self.delegate {
                    dispatch_async(dispatch_get_main_queue()) { delegate.sessionClassifierDidSummarise(exerciseSession) }
                }
            }
        }
    }
    
    public func exerciseConnectivitySessionDidStart(session session: MKExerciseConnectivitySession) {
        let exerciseSession = MKExerciseSession()
        sessions.append(exerciseSession)
        if let delegate = self.delegate {
            dispatch_async(dispatch_get_main_queue()) { delegate.sessionClassifierDidStart(exerciseSession) }
        }
    }
    
    public func sensorDataConnectivityDidReceiveSensorData(accumulated accumulated: MKSensorData, new: MKSensorData, session: MKExerciseConnectivitySession) {
        guard var exerciseSession = sessions.last else { return }
        
        dispatch_async(classificationQueue) {
            if let classified = self.classify(exerciseModelId: session.exerciseModelId, sensorData: new) {
                exerciseSession.classifiedExercises.appendContentsOf(classified)
                if let delegate = self.delegate {
                    dispatch_async(dispatch_get_main_queue()) { delegate.sessionClassifierDidClassify(exerciseSession) }
                }
            }
            self.sessions[self.sessions.count - 1] = exerciseSession
        }
    }
    
}
