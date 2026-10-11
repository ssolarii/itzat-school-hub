import json
from pathlib import Path
subjects = {
 'QR':('Quantitative Reasoning / Math','calculator'), 'DA&M':('Digital Art & Media','monitor'),
 'Span':('Spanish','languages'), 'PE':('Physical Education','activity'), 'CP':('Career Partnership','briefcase'),
 'S&T':('Science & Technology','flask-conical'), 'SDP':('Sustainable Development Projects','sprout'),
 'SIL':('Student Individualized Learning','book-open-check'), 'LA':('Language Arts','book-open'),
 'BS':('Belizean Studies','globe'), 'M':('Maker','hammer'), 'FA':('Fine Art','palette'),
 'LS':('Life Skills','heart-handshake'), 'I':('Internship','briefcase-business'),
 'FL&E':('Financial Literacy & Education','landmark'), 'A':('Assembly','users'),
 'Assembly':('Assembly','users'), 'Super Teams':('Super Teams','users-round'), 'Seminar':('Seminar','presentation')
}
def profile(pairs, dismissal):
 return {'slots':[{'start':a,'end':b} for a,b in pairs],'dismissal':dismissal}
regular = [('08:00','08:55'),('09:00','09:55'),('10:05','11:00'),('11:05','12:00'),('13:00','13:55'),('14:05','15:00')]
quick = [('08:00','08:50'),('08:55','09:45'),('09:55','10:45'),('10:55','11:45'),('12:25','13:10'),('13:15','13:55')]
doc = {'settings':{'anchorDate':'2026-10-13','anchorDay':6,'timezone':'America/Belize','regularDismissal':'15:15'},
 'groups':json.loads(Path('schoolwide-schedules.json').read_text(encoding='utf-8')),
 'subjects':{k:{'name':n,'icon':i} for k,(n,i) in subjects.items()},
 'bellProfiles':{'regular':profile(regular,'15:15'),'quick':profile(quick,'14:10'),'half':profile(regular[:4],'12:20')},
 'calendar':{},'overrides':[],'announcements':[],'banners':[],'teacherAssignments':[], 'archivedGroups':[]}
Path('school-data.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2),encoding='utf-8')
