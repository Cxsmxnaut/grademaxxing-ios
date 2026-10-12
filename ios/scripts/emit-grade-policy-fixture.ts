// All enrollments are invented; expected values come from the owning web GPA module.
import {
	calculateGpaPipelines,
	getCourseWeightBonus,
	isAcademicCourse,
	letterGradePoints
} from '../../src/lib/grades/gpa';
import { GPA_POLICY } from '../../src/lib/grades/gpa-policy';

const cases = [
	{
		name: 'Plus/minus and rigor',
		enrollments: [
			{
				courseName: 'AP Synthetic Math',
				letter: 'A-',
				credits: 5,
				gradeLevel: 11,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'Synthetic English Honours',
				letter: 'B+',
				credits: 2.5,
				gradeLevel: 11,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'AP Synthetic Science',
				letter: 'D',
				credits: 5,
				gradeLevel: 11,
				excludeFromGpa: false,
				academic: true
			}
		]
	},
	{
		name: 'Academic subset',
		enrollments: [
			{
				courseName: 'IB Synthetic History',
				letter: 'A',
				credits: 5,
				gradeLevel: 10,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'Physical Education',
				letter: 'B',
				credits: 5,
				gradeLevel: 10,
				excludeFromGpa: false,
				academic: false
			},
			{
				courseName: "Driver's Education",
				letter: 'A',
				credits: 2.5,
				gradeLevel: 10,
				excludeFromGpa: false,
				academic: false
			}
		]
	},
	{
		name: 'Eligibility, exclusions, and pass/fail',
		enrollments: [
			{
				courseName: 'Synthetic Middle School',
				letter: 'A',
				credits: 5,
				gradeLevel: 8,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'AP Excluded',
				letter: 'A',
				credits: 5,
				gradeLevel: 12,
				excludeFromGpa: true,
				academic: true
			},
			{
				courseName: 'Synthetic Pass',
				letter: 'P',
				credits: 5,
				gradeLevel: 12,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'AP Synthetic Failure',
				letter: 'NP',
				credits: 5,
				gradeLevel: 12,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'Synthetic Missing Credit',
				letter: 'A',
				credits: 0,
				gradeLevel: 12,
				excludeFromGpa: false,
				academic: true
			}
		]
	},
	{
		name: 'Thousandths and normalization',
		enrollments: [
			{
				courseName: 'Synthetic Algebra',
				letter: ' a- ',
				credits: 2.333,
				gradeLevel: 9,
				excludeFromGpa: false,
				academic: true
			},
			{
				courseName: 'Synthetic Honors',
				letter: ' c+ ',
				credits: 4.667,
				gradeLevel: 9,
				excludeFromGpa: false,
				academic: true
			}
		]
	}
];
const titles = [
	'AP Synthetic',
	'IB Synthetic',
	'CAPSTONE',
	'Synthetic Honours',
	'PE',
	'P.E.',
	'Physical Education Honors',
	"Driver's Education",
	'ROTC',
	'Synthetic Art'
];
const grades = ['A+', 'A-', 'B+', 'C-', 'D+', 'F', 'NC', 'NP', 'P', 'CR', 'unknown', ' a '];
process.stdout.write(
	JSON.stringify({
		policyLabel: GPA_POLICY.label,
		gradePoints: grades.map((letter) => ({ letter, points: letterGradePoints(letter) ?? null })),
		coursePolicies: titles.map((title) => ({
			title,
			bonus: getCourseWeightBonus(title),
			academic: isAcademicCourse(title)
		})),
		cases: cases.map((test) => ({ ...test, expected: calculateGpaPipelines(test.enrollments) }))
	}) + '\n'
);
