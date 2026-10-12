// Synthetic only. Regenerate to verify Swift decoding against the real backend XML builder.
import { gradebookXml } from '../../src/lib/server/gradebook-adapter';
import { adaptAttendance } from '../../src/lib/server/studentvue-adapters';
import { adaptDocuments } from '../../src/lib/server/studentvue-api/legacy-adapters';

const period = { name: 'Synthetic semester', index: 2, startDate: '', endDate: '' };
const xml = gradebookXml({
	courses: [
		{
			id: 'synthetic-math',
			period: '1',
			title: 'AP Synthetic Maths',
			room: 'Demo room',
			teacher: 'Ms. Example',
			teacherEmail: '',
			score: 'A-',
			scoreRaw: '92.5',
			missing: '0',
			categories: [
				{
					name: 'Tests',
					weight: '70%',
					points: '190',
					pointsPossible: '200',
					weightedPercentage: '',
					calculatedMark: ''
				},
				{
					name: 'Practice',
					weight: '30%',
					points: '260',
					pointsPossible: '300',
					weightedPercentage: '',
					calculatedMark: ''
				}
			],
			assignments: [
				{
					AssignmentID: 'synthetic-scaled',
					Measure: 'Scaled quiz & review',
					Type: 'Practice',
					DueDate: '10/09/2026',
					Score: '9 out of 10',
					ScoreCalValue: '9',
					ScoreMaxValue: '10',
					Point: '18',
					PointPossible: '20',
					Points: '18 / 20',
					AssignmentPercentage: '90',
					Notes: 'Synthetic teacher note'
				},
				{
					AssignmentID: 'synthetic-ungraded',
					Measure: 'Ungraded project',
					Type: 'Tests',
					Score: 'Not Graded',
					Points: '100 Points Possible',
					CalculationUnavailable: 'true'
				}
			]
		},
		{
			id: 'synthetic-no-marks',
			period: '2',
			title: 'Synthetic Art',
			room: '',
			teacher: '',
			teacherEmail: '',
			score: '',
			scoreRaw: '',
			missing: '',
			categories: [],
			assignments: []
		}
	],
	reportingPeriods: [
		{ name: 'Synthetic first semester', index: 0, startDate: '', endDate: '' },
		period
	],
	selectedPeriod: period,
	detailed: true
});
const attendance = adaptAttendance({
	schoolName: 'Synthetic High School',
	days: [
		{ date: '2026-10-05', type: '11', reason: '' },
		{ date: '2026-10-06', type: '11', reason: 'Tardy' },
		{ date: '2026-10-07', type: '4', reason: '' },
		{ date: '2026-10-08', type: '11', reason: 'Medical' },
		{ date: '2026-10-09', type: '11', reason: 'Holiday' },
		{ date: '2200-01-01', type: '11', reason: '', pending: true }
	],
	courses: [
		{
			course: 'Synthetic Math',
			totals: { present: 28, tardy: 1, absent: 0, excused: 0, unexcused: 0 },
			events: [{ date: '2026-10-06', absence: 'Tardy', reason: 'Late arrival' }]
		},
		{
			course: 'Synthetic English',
			totals: { present: 28, tardy: 0, absent: 1, excused: 1, unexcused: 0 },
			events: [{ date: '2026-10-08', absence: 'Excused', reason: 'Medical' }]
		}
	],
	periods: []
});
const documents = adaptDocuments([
	{
		id: 'c3ludGhldGljLWRvY3VtZW50',
		title: 'Synthetic progress report.pdf',
		date: '10/09/2026',
		category: 'Report'
	}
]);
const message = {
	messagePersonId: '11111111-2222-4333-8444-555555555555',
	subject: 'Synthetic project guide',
	from: { contactDetails1: 'Ms. Example' },
	sendDateTimeFormattedLong: 'October 9, 2026',
	mailRead: false,
	isSystemMessage: false,
	messageText:
		'<p>Review the synthetic project guide &amp; checklist.</p><p><a href="https://example.edu/project">Project page</a></p>',
	attachments: [
		{ attachmentId: '22222222-3333-4444-8555-666666666666', name: 'Synthetic guide.pdf' }
	]
};
const mailbox = {
	folders: [
		{ folderType: 0, name: 'Inbox', folderId: null },
		{ folderType: 1, name: 'Sent', folderId: null }
	],
	messages: [{ ...message, portalFolderType: 0, portalFolderId: null, portalFolderName: 'Inbox' }]
};
const payload = process.argv.includes('--attendance')
	? attendance
	: process.argv.includes('--documents')
		? documents
		: process.argv.includes('--mailbox')
			? mailbox
			: process.argv.includes('--message')
				? message
				: { xml, detailed: true };
process.stdout.write(JSON.stringify(payload) + '\n');
