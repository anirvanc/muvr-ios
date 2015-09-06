#import <Foundation/Foundation.h>
#import "MRModelParameters.h"

///
/// Object holding triple of X, Y, Z values typical for three-dimensional
/// sensors.
///
@interface Threed : NSObject
/// the x component
@property int16_t x;
/// the y component
@property int16_t y;
/// the z component
@property int16_t z;
@end

///
/// Hooks into the decoding of the data from the various devices
///
@protocol MRDeviceDataDelegate

///
/// Called when decoded 3D structure from the given ``sensor``, ``device`` at the ``location``. The ``rows`` is an array of
/// ``Threed*`` instances
///
- (void)deviceDataDecoded3D:(NSArray *)rows fromSensor:(uint8_t)sensor device:(uint8_t)deviceId andLocation:(uint8_t)location;

///
/// Called when decoded 3D structure from the given ``sensor``, ``device`` at the ``location``. The ``rows`` is an array of
/// ``NSNumber*`` instances holding ``int16_t``.
///
- (void)deviceDataDecoded1D:(NSArray *)rows fromSensor:(uint8_t)sensor device:(uint8_t)deviceId andLocation:(uint8_t)location;

@end

///
/// The most coarse exercise detection
///
@protocol MRExerciseBlockDelegate

///
/// Movement detected consistent with some exercise.
///
- (void)exercising;

///
/// The exercise block has ended: either because there is no movement, or the exercise
/// movement became too divergent.
///
- (void)exerciseEnded;

///
/// Movement detected; this movement may become exercise.
///
- (void)moving;

///
/// No movement detected.
///
- (void)notMoving;

@end

///
/// The classification result
///
@interface MRResistanceExercise : NSObject

///
/// Construct this instance with unknown intensity, repetitions and weight
///
- (instancetype)initWithId:(NSString *)id;

/// the classified exercise
@property (readonly) NSString *id;
@end

@interface MRClassifiedResistanceExercise : NSObject

- (instancetype)init:(MRResistanceExercise *)exercise;

//- (instancetype)init:(MRResistanceExercise *)exercise
//         repetitions:(NSNumber *)repetitions
//              weight:(NSNumber *)weight
//           intensity:(NSNumber *)intensity
//       andConfidence:(double)confidence;
//
@property (readonly) MRResistanceExercise* resistanceExercise;
/// if != nil, the number of repetitions
@property (readonly) NSNumber *repetitions;
/// if != nil, the weight
@property (readonly) NSNumber *weight;
/// if != nil, the intensity
@property (readonly) NSNumber *intensity;
/// the confidence
@property (readonly) double confidence;

@end

///
/// Actions executed as results of exercise
///
@protocol MRClassificationPipelineDelegate

///
/// Classification successful, ``result`` holds elements of type ``MRClassifiedExercise``. The
/// implementation of this delegate should examine the array and decide what to do depending on
/// the size of the array. The ``data`` value holds the exported ``muvr::fused_sensor_data`` that
/// was used for the classification.
///
- (void)classificationCompleted:(NSArray *)result fromData:(NSData *)data;

@end

///
/// Actions executed as results of training
///
@protocol MRTrainingPipelineDelegate

///
/// Classification successful, ``result`` holds elements of type ``MRClassifiedExerciseSet``. The
/// implementation of this delegate should examine the array and decide what to do depending on
/// the size of the array. The ``data`` value holds the exported ``muvr::fused_sensor_data`` that
/// was used for the classification.
///
- (void)trainingCompleted:(MRResistanceExercise *)exercise fromData:(NSData *)data;

@end

///
/// Interface to the C++ codebase implementing the preclassification code
///
@interface MRPreclassification : NSObject


///
/// Constructs an instance, sets up the underlying native structures
///
+ (instancetype)training;

///
/// Constructs an instance, sets up the underlying native structures
///
+ (instancetype)classifying:(MRModelParameters *)model;

///
/// Push back the data received from the device at the given location and time
///
- (void)pushBack:(NSData *)data from:(uint8_t)location withHint:(MRResistanceExercise *)plannedExercise;

///
/// Marks the start of the training session for the given exercise
///
- (void)trainingStarted:(MRResistanceExercise *)exercise;

///
/// Marks the end of the training block
///
- (void)trainingCompleted;

///
/// Marks the end of the exercise block
///
- (void)exerciseCompleted;

///
/// exercise block delegate, whose methods get called when entire exercise block is detected.
///
@property id<MRExerciseBlockDelegate> exerciseBlockDelegate;

///
/// provides hooks to be notified of device data arriving / decoding progress
///
@property id<MRDeviceDataDelegate> deviceDataDelegate;

///
/// provides hooks into the classification pipeline
///
@property id<MRClassificationPipelineDelegate> classificationPipelineDelegate;

///
/// provides hooks into the training pipeline
///
@property id<MRTrainingPipelineDelegate> trainingPipelineDelegate;
@end
