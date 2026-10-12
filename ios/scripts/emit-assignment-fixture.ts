/** Synthetic data only. Expected values come from the owning web modules. */
import type { AssignmentEntity } from '../../src/lib/contracts/studentvue/gradebook';
import {
	calculateCourseGradePercentageFromCategories,
	calculateCourseGradePercentageFromTotals,
	getCalculableAssignments,
	getCalculableAssignmentsWithCategories,
	getCategoryAdjustments,
	getPointsByCategory
} from '../../src/lib/grades/assignments/calculations';
import { parseSynergyAssignment } from '../../src/lib/grades/assignments/parsing';
import { calculatePointsNeededForTargetGrade } from '../../src/lib/grades/assignments/target-grade';
import type { Assignment, Category } from '../../src/lib/grades/assignments/types';
import {
	getCalculationCoverage,
	getModelAssignments
} from '../../src/lib/grades/calculation-coverage';
import { getEstimatedGradeTrend, getGradeChartDomain } from '../../src/lib/grades/grade-chart';

const category = (name: string, weight: number, earned: number, possible: number): Category => ({
	name,
	weightPercentage: weight,
	pointsEarned: earned,
	pointsPossible: possible,
	weightedPercentage: 0,
	gradeLetter: ''
});
const wire = (
	id: string,
	earned: string | undefined,
	possible: string | undefined,
	extra: Record<string, string> = {}
) => ({
	GradebookID: id,
	Measure: `Synthetic ${id}`,
	Type: 'Tests',
	Date: '2026-09-01',
	DueDate: '2026-09-02',
	MeasureDescription: '',
	Notes: '',
	Point: earned,
	PointPossible: possible,
	...extra
});
type Wire = ReturnType<typeof wire>;
const parse = (value: Wire) =>
	parseSynergyAssignment(
		Object.fromEntries(
			Object.entries(value)
				.filter(([, value]) => value !== undefined)
				.map(([key, value]) => [`_${key}`, value])
		) as unknown as AssignmentEntity
	);
const cases: {
	name: string;
	official: number;
	categories?: Category[];
	wire: Wire[];
	edit: {
		id: string;
		earned?: number | null;
		possible?: number;
		excluded?: boolean;
		extraCredit?: boolean;
	};
	add?: { category: string; earned: number; possible: number };
}[] = [
	{
		name: 'Official totals with negative hidden denominator',
		official: 85,
		categories: [category('Tests', 70, 80, 100), category('Practice', 30, 95, 100)],
		wire: [
			wire('a', '72', '120'),
			wire('b', '95', '100', { Type: 'Practice', Date: '2026-09-03' })
		],
		edit: { id: 'a', earned: 100 }
	},
	{
		name: 'Precise published points before editing',
		official: 90.45,
		categories: [category('Tests', 100, 9.045, 10)],
		wire: [
			wire('a', '9.0', '10', {
				AssignmentPercentage: '90.45',
				AssignmentPercentagePrecision: '2',
				ScoreCalValue: '18.09',
				ScoreMaxValue: '20'
			})
		],
		edit: { id: 'a', earned: 9.5 }
	},
	{
		name: 'Rounded percentage must not replace precise points',
		official: 90.4,
		wire: [
			wire('a', '9.04', '10.00', { AssignmentPercentage: '90', AssignmentPercentagePrecision: '0' })
		],
		edit: { id: 'a', earned: 9.6 }
	},
	{
		name: 'Extra credit category activates with new work',
		official: 80,
		categories: [category('Tests', 70, 80, 100), category('Practice', 30, 5, 0)],
		wire: [
			wire('a', '80', '100'),
			wire('bonus', '5', '', { Type: 'Practice', Date: '2026-09-03' })
		],
		edit: { id: 'a', earned: 80 },
		add: { category: 'Practice', earned: 8, possible: 10 }
	},
	{
		name: 'Unsupported and zero-weight assignments',
		official: 82,
		categories: [category('Tests', 100, 80, 100), category('Notes', 0, 0, 0)],
		wire: [
			wire('a', '80', '100'),
			wire('raw', undefined, undefined, {
				CalculationUnavailable: 'true',
				ScoreCalValue: '3',
				ScoreMaxValue: '4'
			}),
			wire('unknown', '1', '2', { Type: 'Other' }),
			wire('zero', undefined, undefined, {
				Type: 'Notes',
				CalculationUnavailable: 'true',
				ScoreCalValue: '1',
				ScoreMaxValue: '4'
			}),
			wire('drop', '0', '10', { Notes: ' ( Not For Grading ) teacher note' })
		],
		edit: { id: 'a', earned: 90 }
	},
	{
		name: 'Unweighted points and same-day trend',
		official: 85,
		wire: [
			wire('a', '16', '20'),
			wire('b', '9', '10'),
			wire('c', '8', '10', { Date: '2026-09-03' })
		],
		edit: { id: 'a', excluded: true }
	},
	{
		name: 'Explicit blank earned is zero',
		official: 50,
		wire: [wire('a', '', '10'), wire('b', '10', '10', { Date: '2026-09-03' })],
		edit: { id: 'a', earned: 5 }
	},
	{
		name: 'Missing earned but published percentage',
		official: 80,
		wire: [wire('a', undefined, '10', { AssignmentPercentage: '80' })],
		edit: { id: 'a', earned: 9 }
	},
	{
		name: 'Fraction fallback with bonus',
		official: 85,
		wire: [
			wire('a', undefined, undefined, { Points: '8 / 10' }),
			wire('b', undefined, undefined, { Points: '0.5 /', Date: '2026-09-03' })
		],
		edit: { id: 'a', earned: 9 }
	},
	{
		name: 'Clearing a supported score invalidates estimate',
		official: 80,
		wire: [wire('a', '8', '10')],
		edit: { id: 'a', earned: null }
	}
];
const finite = (value: number) => (Number.isFinite(value) ? value : null);
const percentage = (rows: Assignment[], categories?: Category[]) => {
	const model = getModelAssignments(rows, categories);
	return categories
		? calculateCourseGradePercentageFromCategories(
				getPointsByCategory(getCalculableAssignmentsWithCategories(model)),
				categories
			)
		: calculateCourseGradePercentageFromTotals(getCalculableAssignments(model));
};
const fixtures = cases.map((test) => {
	const original = test.wire.map(parse);
	const adjustments = test.categories ? getCategoryAdjustments(original, test.categories) : [];
	const baseline = percentage([...original, ...adjustments], test.categories);
	const modified: Assignment[] = original.map((row) =>
		row.id !== test.edit.id
			? row
			: {
					...row,
					...('earned' in test.edit ? { pointsEarned: test.edit.earned ?? undefined } : {}),
					...('possible' in test.edit ? { pointsPossible: test.edit.possible } : {}),
					...('excluded' in test.edit ? { notForGrade: test.edit.excluded! } : {}),
					...('extraCredit' in test.edit ? { extraCredit: test.edit.extraCredit! } : {})
				}
	);
	if (test.add)
		modified.push({
			...original[0],
			name: 'What-if',
			id: 'new',
			category: test.add.category,
			pointsEarned: test.add.earned,
			pointsPossible: test.add.possible,
			officialPercentage: undefined,
			publishedPoints: undefined,
			calculationPointsEarned: undefined,
			newHypothetical: true,
			notForGrade: false,
			extraCredit: false
		});
	const calculated = percentage([...modified, ...adjustments], test.categories);
	const validEdit = test.edit.earned !== null;
	const modeled = getModelAssignments([...modified, ...adjustments], test.categories);
	const targetCategory = test.add?.category ?? 'Tests';
	const targetOptions = test.categories
		? {
				hasCategories: true as const,
				otherAssignments: getCalculableAssignmentsWithCategories(modeled),
				gradeCategoryWeightProportions: new Map(
					test.categories.map((c) => [c.name, c.weightPercentage / 100])
				),
				assignmentCategoryName: targetCategory
			}
		: { hasCategories: false as const, otherAssignments: getCalculableAssignments(modeled) };
	const coverage = getCalculationCoverage(modified, test.categories);
	const trend = getEstimatedGradeTrend(original, test.categories, test.official).map((point) => ({
		date: new Date(point.observedAt).toISOString().slice(0, 10),
		percentage: point.percentage,
		assignments: point.assignmentNames
	}));
	return {
		...test,
		categories:
			test.categories?.map((c) => ({
				name: c.name,
				weight: c.weightPercentage,
				earned: c.pointsEarned,
				possible: c.pointsPossible
			})) ?? [],
		parsed: original.map((a) => ({
			id: a.id,
			earned: a.pointsEarned ?? null,
			possible: a.pointsPossible ?? null,
			precise: a.calculationPointsEarned ?? null,
			extraCredit: a.extraCredit,
			excluded: a.notForGrade
		})),
		baseline: finite(baseline),
		projected: validEdit ? finite(test.official + calculated - baseline) : null,
		omitted: coverage.omittedAssignmentCount,
		partial: !coverage.complete || Math.abs(baseline - test.official) > 0.25,
		targetCategory,
		needed: validEdit
			? finite(
					calculatePointsNeededForTargetGrade({
						...targetOptions,
						targetGradePercentage: 90 - (test.official - baseline),
						assignmentPointsPossible: 20
					})
				)
			: null,
		trend,
		domain: getGradeChartDomain(trend.map((p) => p.percentage))
	};
});
process.stdout.write(JSON.stringify(fixtures) + '\n');
