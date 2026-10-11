import json
from pathlib import Path

workspace = Path(r'C:\Users\solari\Documents\SAV5')
visuals = Path(r'C:\Users\solari\.codex\visualizations\2026\10\10\01a123a6-18ca-7211-adf2-08e259014630')
data = {}
for name in ['schedules-years-1-2.json', 'schedules-years-3-4.json']:
    data.update(json.loads((workspace / name).read_text(encoding='utf-8-sig')))
(workspace / 'schoolwide-schedules.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
source = (visuals / 'purple-orange-school-concept.html').read_text(encoding='utf-8-sig')
markup = source.split('<style>', 1)[0]
markup = markup.replace('4HST demonstrates an unpublished class', 'all 11 supplied groups; missing rooms stay unassigned')
markup = markup.replace('3CS subjects and rooms from your timetable', 'subjects and rooms from your uploaded timetables')
markup = markup.replace('sample dates, notices and bell times', 'sample calendar and notices; regular dismissal provisional')
markup = markup.replace('<label class="form-check">', '<label class="form-label">Bell schedule<select class="form-select" id="isa-bell"><option value="regular">Regular</option><option value="quick">Quick exit</option><option value="half">Half day</option></select></label>\n    <label class="form-check">', 1)
markup = markup.replace('>Today</button>', '><i data-lucide="clock-3" aria-hidden="true"></i>Today</button>')
markup = markup.replace('>Next school day</button>', '><i data-lucide="arrow-right" aria-hidden="true"></i>Next school day</button>')
markup = markup.replace('>Week</button>', '><i data-lucide="calendar-days" aria-hidden="true"></i>Week</button>')
markup = markup.replace('>7-day cycle</a>', '><i data-lucide="calendar-range" aria-hidden="true"></i>Calendar</a>')
markup = markup.replace('>Updates</a>', '><i data-lucide="megaphone" aria-hidden="true"></i>Updates</a>')
markup = markup.replace('<h2>The 7-day cycle</h2><p>Find any day without counting ahead.</p>', '<h2><i data-lucide="calendar-range" aria-hidden="true"></i>Cycle calendar</h2><p>Pick a day to see its classes.</p>')
markup = markup.replace('<nav class="isa-day-jumps" aria-label="Jump to a cycle day"></nav>', '<label class="isa-day-jumps">Cycle day<select id="isa-cycle-day" aria-label="Cycle day">' + ''.join(f'<option value="{d}" {"selected" if d == 5 else ""}>Day {d}{" · Half day" if d == 7 else ""}</option>' for d in range(1, 8)) + '</select></label>')
markup = markup.replace('<h2>School updates</h2>', '<h2><i data-lucide="megaphone" aria-hidden="true"></i>School updates</h2>')
css = source.split('<style>', 1)[1].split('</style>', 1)[0]
css = css.replace('.isa-subject summary', '.isa-subject-code')
markup = (workspace / 'student-desktop-template.html').read_text(encoding='utf-8')
css = (workspace / 'student-desktop.css').read_text(encoding='utf-8')
runtime = (workspace / 'schoolwide-concept-runtime.js').read_text(encoding='utf-8')
output = markup + '<style>' + css + '</style>\n<script>\nconst schoolSchedules = ' + json.dumps(data, ensure_ascii=False) + ';\n' + runtime + '\n</script>\n'
(visuals / 'schoolwide-student-concept.html').write_text(output, encoding='utf-8')
print(f'Integrated {len(data)} class groups; wrote schoolwide-student-concept.html')
