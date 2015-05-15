#import "MRPreclassification.h"
#import "MuvrPreclassification/include/easylogging++.h"
#import "MuvrPreclassification/include/sensor_data.h"
#import "MuvrPreclassification/include/device_data_decoder.h"
#import "MuvrPreclassification/include/svm_classifier.h"
#import "MuvrPreclassification/include/svm_classifier_factory.h"
#import "MuvrPreclassification/include/classifier_loader.h"
#import "MuvrPreclassification/include/export.h"
#import "MuvrPreclassification/include/ensemble_classifier.h"

using namespace muvr;

INITIALIZE_EASYLOGGINGPP;

class const_exercise_decider : public exercise_decider {
public:
    virtual exercise_result has_exercise(const raw_sensor_data& source, exercise_context &context) override {
        return yes;
    }
};

class monitoring_exercise_decider : public exercise_decider {
private:
    exercise_context m_last_context;
public:
    virtual exercise_result has_exercise(const raw_sensor_data& source, exercise_context &context) override {
        const auto r = exercise_decider::has_exercise(source, context);
        m_last_context = context;
        return r;
    }
    
    exercise_context last_context() const { return m_last_context; }
};

#pragma MARK - Threed implementation

@implementation Threed
@end

#pragma MARK - MRResistanceExerciseSet implementation

@implementation MRResistanceExerciseSet

- (instancetype)init:(MRResistanceExercise *)exercise {
    self = [super init];
    _sets = [NSArray arrayWithObject:exercise];
    return self;
}

- (instancetype)initWithSets:(NSArray *)sets {
    self = [super init];
    _sets = sets;
    return self;
}

- (double)confidence {
    if (_sets.count == 0) return 0;
    
    double sum = 0;
    for (MRResistanceExercise *set : _sets) {
        sum += set.confidence;
    }
    return sum / _sets.count;
}

- (MRResistanceExercise *)objectAtIndexedSubscript:(int)idx {
    return [_sets objectAtIndexedSubscript:idx];
}

@end

#pragma MARK - MRResistanceExercise implementation

@implementation MRResistanceExercise

- (instancetype)initWithExercise:(NSString *)exercise andConfidence:(double)confidence {
    self = [super init];
    _exercise = exercise;
    _confidence = confidence;
    return self;
}

- (instancetype)initWithExercise:(NSString *)exercise repetitions:(NSNumber *)repetitions weight:(NSNumber *)weight intensity:(NSNumber *)intensity andConfidence:(double)confidence {
    self = [super init];
    
    _exercise = exercise;
    _confidence = confidence;
    _repetitions = repetitions;
    _weight = weight;
    _intensity = intensity;
    
    return self;
}

@end

@implementation MRPreclassification {
    std::unique_ptr<sensor_data_fuser> m_fuser;
    std::unique_ptr<ensemble_classifier> m_classifier;
}

- (instancetype)init {
    self = [super init];
    m_fuser = std::unique_ptr<sensor_data_fuser>(new sensor_data_fuser(std::shared_ptr<movement_decider>(new movement_decider()),
                                                                       std::shared_ptr<exercise_decider>(new exercise_decider())));
    NSString *fullPath = [[NSBundle mainBundle] pathForResource:@"svm-model-bicep_curl-features" ofType:@"libsvm"];
    std::string libsvm([fullPath stringByDeletingLastPathComponent].UTF8String);
    fullPath = [[NSBundle mainBundle] pathForResource:@"svm-model-bicep_curl-features" ofType:@"scale"];
    std::string scale(fullPath.UTF8String);
    
    auto classifiers = muvr::classifier_loader().load(libsvm);
    m_classifier = std::unique_ptr<muvr::ensemble_classifier>(new ensemble_classifier::ensemble_classifier(classifiers));
    
    return self;
}

- (void)pushBack:(NSData *)data from:(uint8_t)location withHint:(MRResistanceExercise *)plannedExercise {
    // core processing
    const uint8_t *buf = reinterpret_cast<const uint8_t*>(data.bytes);
    raw_sensor_data decoded = decode_single_packet(buf);
    sensor_data_fuser::fusion_result fusionResult = m_fuser->push_back(decoded, sensor_location_t::wrist, 0);

    // hooks & delegates
    
    // first, handle the device data stuff
    if (self.deviceDataDelegate != nil) {
        Mat data = decoded.data();
        
        NSMutableArray *values = [[NSMutableArray alloc] init];
        for (int i = 0; i < data.rows; ++i) {
            if (data.cols == 3) {
                Threed *t = [[Threed alloc] init];
                t.x = data.at<int16_t>(i, 0);
                t.y = data.at<int16_t>(i, 1);
                t.z = data.at<int16_t>(i, 2);
                [values addObject:t];
            } else if (data.cols == 1) {
                [values addObject:[NSNumber numberWithInt:data.at<int16_t>(i, 0)]];
            } else {
                throw std::runtime_error("unreportable data dimension");
            }
        }
        [self.deviceDataDelegate deviceDataDecoded3D:values fromSensor:decoded.type() device:decoded.device_id() andLocation:location];
    }

    // second, the exercise blocks
    if (self.exerciseBlockDelegate != nil) {
        switch (fusionResult.type()) {
            case sensor_data_fuser::fusion_result::not_moving:
                [self.exerciseBlockDelegate notMoving];
                break;
            case sensor_data_fuser::fusion_result::moving:
                [self.exerciseBlockDelegate moving];
                break;
            case sensor_data_fuser::fusion_result::exercising:
                [self.exerciseBlockDelegate exercising];
                break;
            case sensor_data_fuser::fusion_result::exercise_ended:
                [self.exerciseBlockDelegate exerciseEnded];
                break;
        }
    }
    
    if (fusionResult.type() != sensor_data_fuser::fusion_result::exercise_ended) return;
    
    // finally, the classification pipeline
    svm_classifier::classification_result result = m_classifier->classify(fusionResult.fused_exercise_data());
    
    NSMutableArray *transformedClassificationResult = [NSMutableArray array];

    if (result.exercises().size() > 0) {
            
        // for now we just take the first and only identified exercise if there is any
        svm_classifier::classified_exercise classified_exercise = result.exercises()[0];
            
        MRResistanceExercise *exercise = [[MRResistanceExercise alloc]
                                            initWithExercise:[NSString stringWithCString:classified_exercise.exercise_name().c_str()encoding:[NSString defaultCStringEncoding]]
                                            repetitions:@(classified_exercise.repetitions())
                                            weight: @(classified_exercise.weight())
                                            intensity: @(classified_exercise.intensity())
                                            andConfidence: classified_exercise.confidence()];
        
        MRResistanceExerciseSet *exercise_set = [[MRResistanceExerciseSet alloc] init:exercise];
        [transformedClassificationResult addObject:exercise_set];
    }
    
    // the hooks
    if (self.classificationPipelineDelegate != nil) {
        std::ostringstream os;
        os << "[";
        for (int i = 0; i < fusionResult.fused_exercise_data().size(); ++i) {
            if (i > 0) os << ",";
            export_data(os, fusionResult.fused_exercise_data()[i]);
        }
        os << "]";

        NSData *data = [[NSString stringWithUTF8String:os.str().c_str()] dataUsingEncoding:NSUTF8StringEncoding];
        [self.classificationPipelineDelegate classificationCompleted:transformedClassificationResult fromData:data];
    }
}

@end
