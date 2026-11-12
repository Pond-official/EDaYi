import localUnitTest from './LocalUnit.test';
import textSplitTest from './TextSplit.test';
import scheduleParserTest from './ScheduleParser.test';
import gradeParserTest from './GradeParser.test';
import trainingPlanParserTest from './TrainingPlanParser.test';
import studentParserTest from './StudentParser.test';
import examDateUtilsTest from './ExamDateUtils.test';

export default function testsuite() {
  localUnitTest();
  textSplitTest();
  scheduleParserTest();
  gradeParserTest();
  trainingPlanParserTest();
  studentParserTest();
  examDateUtilsTest();
}
