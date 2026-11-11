import localUnitTest from './LocalUnit.test';
import textSplitTest from './TextSplit.test';
import scheduleParserTest from './ScheduleParser.test';
import gradeParserTest from './GradeParser.test';
import trainingPlanParserTest from './TrainingPlanParser.test';
import studentParserTest from './StudentParser.test';

export default function testsuite() {
  localUnitTest();
  textSplitTest();
  scheduleParserTest();
  gradeParserTest();
  trainingPlanParserTest();
  studentParserTest();
}
