import localUnitTest from './LocalUnit.test';
import textSplitTest from './TextSplit.test';
import scheduleParserTest from './ScheduleParser.test';
import gradeParserTest from './GradeParser.test';
import trainingPlanParserTest from './TrainingPlanParser.test';
import studentParserTest from './StudentParser.test';
import examDateUtilsTest from './ExamDateUtils.test';
import nightSwitchUtilsTest from './NightSwitchUtils.test';
import libraryRepositoryTest from './LibraryRepository.test';
import ehallRepositoryTest from './EhallRepository.test';
import examShareTextTest from './ExamShareText.test';
import examShareLinkTest from './ExamShareLink.test';
import termWeekUtilsTest from './TermWeekUtils.test';
import aesGcmTest from './AesGcm.test';

export default function testsuite() {
  localUnitTest();
  textSplitTest();
  scheduleParserTest();
  gradeParserTest();
  trainingPlanParserTest();
  studentParserTest();
  examDateUtilsTest();
  nightSwitchUtilsTest();
  libraryRepositoryTest();
  ehallRepositoryTest();
  examShareTextTest();
  examShareLinkTest();
  termWeekUtilsTest();
  aesGcmTest();
}
