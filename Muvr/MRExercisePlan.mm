#import <Foundation/Foundation.h>
#import "MRExercisePlan.h"
#import "MuvrPreclassification/include/exercise_plan.h"

using namespace muvr;

@implementation MRResistanceExercise (planned_exercise)

+ (instancetype)plannedExercise:(const planned_exercise &)plannedExercise {
    assert(plannedExercise.tag == planned_exercise::resistance);
    auto rex = plannedExercise.resistance_exercise;
    
    NSString* exercise = [NSString stringWithUTF8String:plannedExercise.exercise.c_str()];
    NSNumber* repetitions = rex.repetitions != UNKNOWN_REPETITIONS ? [NSNumber numberWithInt:rex.repetitions] : nil;
    NSNumber* intensity = rex.intensity > UNKNOWN_INTENSITY ? [NSNumber numberWithDouble:rex.intensity] : nil;
    NSNumber* weight = rex.weight > UNKNOWN_WEIGHT ? [NSNumber numberWithDouble:rex.weight] : nil;
    
    return [[MRResistanceExercise alloc] initWithExercise:exercise repetitions:repetitions weight:weight intensity:intensity andConfidence:1];
}

- (BOOL)isRoughlyEqual:(id)object {
    if (object == NULL) return NO;
    if (![object isKindOfClass:[self class]]) return NO;

    MRResistanceExercise* other = (MRResistanceExercise *)object;
    return [self.exercise isEqualToString:other.exercise];
}

@end

@implementation MRRest
- (instancetype)init:(const planned_rest &)rest {
    self = [super init];
    _minimumDuration = rest.minimum_duration;
    _maximumDuration = rest.maximum_duration;
    _minimumHeartRate = rest.heart_rate;
    return self;
}

- (BOOL)isRoughlyEqual:(id)object {
    if (object == NULL) return NO;
    if (![object isKindOfClass:[self class]]) return NO;
    
    return YES;
}

@end

@implementation MRExercisePlanItem

- (instancetype)init:(const exercise_plan_item &)item {
    self = [super init];

    switch (item.tag) {
        case muvr::exercise_plan_item::rest:
            _rest = [[MRRest alloc] init:item.rest_item];
            break;
        case muvr::exercise_plan_item::exercise:
            switch (item.exercise_item.tag) {
                case muvr::planned_exercise::resistance:
                    _resistanceExercise = [MRResistanceExercise plannedExercise:item.exercise_item];
                    break;
                default:
                    @throw @"Match error";
            }
    }
    
    return self;
}

- (NSString *)description {
    if (_rest != NULL) {
        return [NSString stringWithFormat:@"%f", _rest.minimumDuration];
    }
    if (_resistanceExercise != NULL) {
        return [NSString stringWithFormat:@"%@, %@ reps, %@ weight, %@ intensity", _resistanceExercise.exercise, _resistanceExercise.repetitions, _resistanceExercise.weight, _resistanceExercise.intensity];
    }
    
    @throw @"MRExercisePlanItem in illegal state.";
}

- (BOOL)isRoughlyEqual:(id)object {
    if (![object isKindOfClass:[self class]]) return NO;
    
    MRExercisePlanItem *other = (MRExercisePlanItem *)object;
    if (_rest != NULL) return [_rest isRoughlyEqual:other.rest];
    if (_resistanceExercise != NULL) return [_resistanceExercise isRoughlyEqual:other.resistanceExercise];

    return NO;
}

@end

@implementation MRExercisePlanDeviation

- (instancetype)init:(const exercise_plan_deviation &)deviation {
    self = [super init];
    
    _actual = [[MRExercisePlanItem alloc] init:deviation.actual];
    _planned = [[MRExercisePlanItem alloc] init:deviation.planned];
    
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ x %@", _planned.description, _actual.description];
}

@end

@implementation MRExercisePlan {
    std::unique_ptr<exercise_plan> exercisePlan;
    NSArray *empty;
    NSMutableArray *completed;
    MRExercisePlanItem *current;
}

+ (instancetype)planWithResistanceExercises:(NSArray *)resistanceExercises {
    return [[MRExercisePlan alloc] initWithResistanceExercises:resistanceExercises];
}

+ (instancetype)adHoc {
    return [[MRExercisePlan alloc] init];
}

- (planned_exercise)fromMRResistanceExercise:(MRResistanceExercise *)exercise {
    double intensity = exercise.intensity != nil ? exercise.intensity.doubleValue : 0;
    double weight = exercise.weight != nil ? exercise.weight.doubleValue : 0;
    uint repetitions = exercise.repetitions != nil ? exercise.repetitions.intValue : 0;
    return planned_exercise(std::string(exercise.exercise.UTF8String), intensity, weight, repetitions);
}

- (instancetype)init {
    self = [super init];
    empty = [[NSArray alloc] init];
    completed = [[NSMutableArray alloc] init];
    current = NULL;
    return self;
}

- (instancetype)initWithResistanceExercises:(NSArray *)resistanceExercises {
    self = [super init];
    std::vector<exercise_plan_item> plan;
    for (MRResistanceExercise *exercise : resistanceExercises) {
        plan.push_back([self fromMRResistanceExercise:exercise]);
    }
    
    current = NULL;
    exercisePlan = std::unique_ptr<exercise_plan>(new simple_exercise_plan(plan));
    
    return self;
}

- (NSArray *)convert:(const std::vector<exercise_plan_item> &)items {
    NSMutableArray* result = [[NSMutableArray alloc] init];
    for (const auto &x : items) {
        [result addObject:[[MRExercisePlanItem alloc] init:x]];
    }
    return result;
}

- (MRExercisePlanItem *)exercise:(MRResistanceExercise *)actual {
    planned_exercise pe = [self fromMRResistanceExercise:actual];
    if (!exercisePlan) {
        [completed addObject:[[MRExercisePlanItem alloc] init:pe]];
        return NULL;
    }
    timestamp_t now = (timestamp_t)(CFAbsoluteTimeGetCurrent() * 1000);

    const auto &x = exercisePlan->exercise(pe, now);
    
    MRExercisePlanItem *c = NULL;
    if (x) c = [[MRExercisePlanItem alloc] init:*x];

    if (_delegate != NULL && c != NULL && ![c isRoughlyEqual:current]) [_delegate currentItem:c changedFromPrevious:current];
    current = c;
    
    return c;
}

- (MRExercisePlanItem *)noExercise {
    if (!exercisePlan) return NULL;
    timestamp_t now = (timestamp_t)(CFAbsoluteTimeGetCurrent() * 1000);
    
    const auto &x = exercisePlan->no_exercise(now);
    
    MRExercisePlanItem *c = NULL;
    if (x) c = [[MRExercisePlanItem alloc] init:*x];

    if (_delegate != NULL && c != NULL && ![c isRoughlyEqual:current]) [_delegate currentItem:c changedFromPrevious:current];
    current = c;
    
    return c;
}

- (NSArray *)completed {
    if (!exercisePlan) return completed;
    return [self convert:exercisePlan->completed()];
}

- (NSArray *)todo {
    if (!exercisePlan) return empty;
    return [self convert:exercisePlan->todo()];
}

- (MRExercisePlanItem *)current {
    if (!exercisePlan) return NULL;
    const auto &x = exercisePlan->current();
    if (x) return [[MRExercisePlanItem alloc] init:*x];
    return NULL;
}

- (NSArray *)deviations {
    if (!exercisePlan) return empty;
    NSMutableArray* result = [[NSMutableArray alloc] init];
    for (const auto &x : exercisePlan->deviations()) {
        [result addObject:[[MRExercisePlanDeviation alloc] init:x]];
    }
    return result;
}

- (double)progress {
    if (!exercisePlan) return 0;
    return exercisePlan->progress();
}

@end