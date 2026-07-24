/**
 * Symptom red-flag rules, matched against the patient's own words in English,
 * Bengali and Hindi.
 *
 * Deliberately keyword-driven rather than model-driven: a regex cannot be
 * talked out of firing. The model is allowed to *raise* urgency later, never to
 * lower what these rules decide. Matching is generous on purpose — a false
 * "please get checked" is a far cheaper error than a missed myocardial
 * infarction.
 */

export const RED_FLAG_RULES = Object.freeze([
  {
    id: 'RF_CHEST_PAIN',
    label: 'Chest pain or pressure',
    urgency: 'emergency',
    alertType: 'chest_pain',
    patterns: [
      /\bchest\s*(pain|pressure|tightness|discomfort|heavy|heaviness|burning)\b/i,
      /\bpain\s+in\s+(my\s+)?chest\b/i,
      /\b(crushing|squeezing)\s+(pain|sensation)\b/i,
      /\bheart\s*attack\b/i,
      /বুকে?\s*(ব্যথা|ব্যাথা|যন্ত্রণা|চাপ|ভার)/,
      /বুক\s*ধড়ফড়/,
      /(सीने|छाती|सिने)\s*में\s*(दर्द|जलन|भारीपन|दबाव)/,
      /दिल\s*का\s*दौरा/,
    ],
  },
  {
    id: 'RF_BREATHING',
    label: 'Difficulty breathing',
    urgency: 'emergency',
    alertType: 'breathing_difficulty',
    patterns: [
      /\b(can(no|')?t|cannot|unable to|difficulty|trouble|hard to)\s+breath\w*/i,
      /\b(short(ness)?\s+of\s+breath|breathless|gasping|suffocat\w+|choking)\b/i,
      /\bbreathing\s+(problem|difficulty|trouble|issue)\b/i,
      /শ্বাস\s*(কষ্ট|নিতে\s*কষ্ট|প্রশ্বাসে\s*সমস্যা)/,
      /দম\s*(বন্ধ|আটকে)/,
      /(सांस|साँस)\s*(लेने\s*में\s*)?(तकलीफ|दिक्कत|परेशानी|फूल)/,
      /दम\s*घुट/,
    ],
  },
  {
    id: 'RF_VISION_LOSS',
    label: 'Sudden vision loss',
    urgency: 'emergency',
    alertType: 'vision_loss',
    patterns: [
      /\bsudden\w*\s+(vision\s+loss|blind|can(no|')?t\s+see|loss\s+of\s+vision)/i,
      /\b(lost|losing)\s+(my\s+)?(vision|eyesight|sight)\b/i,
      /\bcurtain\s+(over|across)\s+(my\s+)?(eye|vision)\b/i,
      /\b(flashes|floaters)\s+(suddenly|and\s+shadow)/i,
      /(হঠাৎ|আচমকা)[^।.!?]{0,25}(চোখে|দেখতে|দৃষ্টি)/,
      /(চোখে\s*দেখতে\s*পাচ্ছি\s*না|অন্ধ\s*হয়ে)/,
      /(अचानक|एकाएक)[^।.!?]{0,25}(दिखाई|दिखना|नज़र|नजर)/,
      /(दिखाई\s*नहीं\s*दे|अंधा\s*हो|नज़र\s*चली)/,
    ],
  },
  {
    id: 'RF_UNCONSCIOUS',
    label: 'Loss of consciousness or seizure',
    urgency: 'emergency',
    alertType: 'severe_hypoglycaemia',
    patterns: [
      /\b(unconscious|unresponsive|passed\s+out|blacked\s+out|fainted|collapsed)\b/i,
      /\b(seizure|convulsion|fits|fitting)\b/i,
      /\bnot\s+waking\s+up\b/i,
      /(অজ্ঞান|জ্ঞান\s*হারা|সংজ্ঞাহীন|খিঁচুনি|মূর্ছা)/,
      /(बेहोश|होश\s*नहीं|मूर्छा|दौरा\s*पड़|मिर्गी|ऐंठन)/,
    ],
  },
  {
    id: 'RF_STROKE',
    label: 'Stroke warning signs',
    urgency: 'emergency',
    alertType: 'other',
    patterns: [
      // Patients write "my face is drooping" far more often than "face droop",
      // so these allow a short connector rather than requiring adjacency.
      /\b(face|mouth|smile)\b[^.!?]{0,20}\b(droop\w*|twisted|crooked|not\s+moving)\b/i,
      /\b(slurred|slurring)\s+speech\b/i,
      /\bspeech\b[^.!?]{0,20}\b(slurr\w*|unclear|not\s+clear)\b/i,
      /\b(weakness|numbness|paralysis)\s+(on\s+)?(one\s+side|left\s+side|right\s+side)\b/i,
      /\bcan(no|')?t\s+(move|lift)\s+(my\s+)?(arm|leg|hand)\b/i,
      /\bworst\s+headache\b/i,
      /(মুখ\s*বেঁকে|কথা\s*জড়িয়ে|একদিক\s*অবশ|পক্ষাঘাত|স্ট্রোক)/,
      /(मुँह\s*टेढ़ा|मुंह\s*टेढ़ा|बोलने\s*में\s*दिक्कत|एक\s*तरफ\s*कमज़ोर|लकवा|पक्षाघात)/,
    ],
  },
  {
    id: 'RF_SEVERE_HYPO_SYMPTOMS',
    label: 'Severe hypoglycaemia symptoms',
    urgency: 'emergency',
    alertType: 'severe_hypoglycaemia',
    patterns: [
      /\b(cold\s+sweat|profuse\s+sweating)\b.*\b(shak|trembl|confus|dizz)/i,
      /\b(confused|disoriented|can(no|')?t\s+think\s+straight)\b.*\b(sugar|hypo|insulin)/i,
      /\bsugar\s+(is\s+)?(very\s+)?low\b.*\b(shak|sweat|confus|faint)/i,
      /\b(hypo|hypoglyc\w+)\b.*\b(severe|bad|can(no|')?t)/i,
      /(খুব\s*ঘাম|ঠান্ডা\s*ঘাম)[^।.!?]{0,30}(কাঁপ|মাথা\s*ঘোর|অজ্ঞান)/,
      /(ठंडा\s*पसीना|बहुत\s*पसीना)[^।.!?]{0,30}(कांप|कँप|चक्कर|बेहोश)/,
    ],
  },
  {
    id: 'RF_DKA',
    label: 'Possible diabetic ketoacidosis',
    urgency: 'emergency',
    alertType: 'dka_suspected',
    patterns: [
      /\b(vomit\w*|throwing\s+up)\b[^.!?]{0,60}\b(sugar|abdominal|stomach\s+pain|breath)/i,
      /\bfruity\s+(smell|breath|odou?r)\b/i,
      /\bketones?\b[^.!?]{0,30}\b(high|positive|large|moderate)\b/i,
      /\b(deep|rapid|heavy)\s+breathing\b[^.!?]{0,40}\b(sugar|diabet)/i,
      /(বমি)[^।.!?]{0,40}(পেটে\s*ব্যথা|সুগার|শ্বাস)/,
      /(কিটোন|কিটোএসিডোসিস)/,
      /(उल्टी)[^।.!?]{0,40}(पेट\s*में\s*दर्द|शुगर|सांस)/,
      /(कीटोन|कीटोएसिडोसिस)/,
    ],
  },
  {
    // Hyperosmolar hyperglycaemic state. Distinguished from DKA by the absence
    // of ketones and by drowsiness/confusion dominating the picture. Mortality
    // is higher than DKA, and it is largely a disease of older Type 2 patients
    // — exactly this clinic's population.
    id: 'RF_HHS',
    label: 'Possible hyperosmolar hyperglycaemic state',
    urgency: 'emergency',
    alertType: 'hhs_suspected',
    patterns: [
      /\b(confus\w+|drowsy|drowsiness|very\s+sleepy|not\s+making\s+sense|disorient\w+)\b[^.!?]{0,60}\b(sugar|glucose|diabet\w+|thirst)/i,
      /\b(sugar|glucose)\b[^.!?]{0,40}\b(very\s+high|over\s+500|above\s+500|600)\b[^.!?]{0,40}\b(confus\w+|drowsy|weak|thirst)/i,
      /\b(extreme|severe|constant|unquenchable)\s+thirst\b[^.!?]{0,50}\b(confus\w+|drowsy|weak|passing\s+urine)/i,
      /(খুব\s*ঘুম|ঝিমুনি|বিভ্রান্ত|অস্পষ্ট\s*কথা)[^।.!?]{0,50}(সুগার|তেষ্টা|প্রস্রাব)/,
      /(অতিরিক্ত\s*তেষ্টা|খুব\s*পিপাসা)[^।.!?]{0,50}(ঝিমুনি|বিভ্রান্ত|দুর্বল)/,
      /(बहुत\s*नींद|सुस्ती|भ्रम|होश\s*में\s*नहीं)[^।.!?]{0,50}(शुगर|प्यास|पेशाब)/,
      /(बहुत\s*ज्यादा\s*प्यास|अत्यधिक\s*प्यास)[^।.!?]{0,50}(सुस्ती|भ्रम|कमज़ोर)/,
    ],
  },
  {
    // Thyroid storm. Requires co-occurrence of thyroid context with fever,
    // racing heart or agitation — a Graves' patient saying "my heart is
    // racing and I have a fever" is a genuine emergency, but "my thyroid
    // report came" must not fire.
    id: 'RF_THYROID_STORM',
    label: 'Possible thyroid storm',
    urgency: 'emergency',
    alertType: 'thyroid_storm',
    patterns: [
      /\bthyroid\s*storm\b/i,
      /\b(thyroid|thyrotox\w+|graves|hyperthyroid\w*)\b[^.!?]{0,70}\b(fever|high\s+temperature|racing\s+heart|heart\s+racing|palpitation\w*|very\s+fast\s+(heart|pulse)|confus\w+|agitat\w+|trembl\w+\s+badly)\b/i,
      /\b(fever|racing\s+heart|heart\s+racing|palpitation\w*)\b[^.!?]{0,70}\b(thyroid|thyrotox\w+|graves|hyperthyroid\w*)\b/i,
      /(থাইরয়েড|থাইরোটক্সিক|গ্রেভস)[^।.!?]{0,60}(জ্বর|বুক\s*ধড়ফড়|হৃদস্পন্দন|কাঁপুনি|বিভ্রান্ত)/,
      /(जबर्दस्त\s*)?(थायराइड|थायरॉइड|ग्रेव्स)[^।.!?]{0,60}(बुखार|धड़कन|दिल\s*तेज|कंपकंपी|घबराहट|भ्रम)/,
    ],
  },
  {
    // Adrenal crisis. Anyone on long-term steroids or with Addison's who is
    // vomiting and cannot keep tablets down is at risk within hours; the
    // treatment is hydrocortisone and it cannot wait for an appointment.
    id: 'RF_ADRENAL_CRISIS',
    label: 'Possible adrenal crisis',
    urgency: 'emergency',
    alertType: 'adrenal_crisis',
    patterns: [
      /\badrenal\s*(crisis|failure|insufficiency)\b/i,
      /\b(addison\w*)\b[^.!?]{0,70}\b(vomit\w*|weak|dizzy|faint|collapse|unwell|pain)\b/i,
      // `steroid\w*` not `steroid` — \b does not fall between "steroid" and
      // the "s" of "steroids", which is how patients actually write it.
      /\b(steroid\w*|hydrocortisone|prednisolone|prednisone|fludrocortisone)\b[^.!?]{0,70}\b(vomit\w*|can(no|')?t\s+keep\s+(it|them|tablets)\s+down|missed\s+dose|stopped)\b[^.!?]{0,50}\b(weak|dizzy|faint|unwell|collapse|pain)\b/i,
      /\b(severe\s+weakness|collapsing|about\s+to\s+faint)\b[^.!?]{0,60}\b(steroid\w*|hydrocortisone|addison\w*)\b/i,
      /(অ্যাড্রিনাল|অ্যাডিসন|স্টেরয়েড|হাইড্রোকর্টিসোন)[^।.!?]{0,60}(বমি|খুব\s*দুর্বল|মাথা\s*ঘুরছে|অজ্ঞান)/,
      /(एड्रिनल|एडिसन|स्टेरॉयड|हाइड्रोकोर्टिसोन)[^।.!?]{0,60}(उल्टी|बहुत\s*कमज़ोर|चक्कर|बेहोश)/,
    ],
  },
  {
    id: 'RF_FOOT_INFECTION',
    label: 'Severe diabetic foot infection',
    urgency: 'emergency',
    alertType: 'foot_infection',
    patterns: [
      /\bfoot\b[^.!?]{0,60}\b(black|gangrene|necro\w+|rotting|dead\s+tissue)\b/i,
      /\b(black|blue|dark)\s+(toe|toes|foot|skin)\b/i,
      // "my toe is black" / "the wound has turned dark"
      /\b(toe|toes|foot|feet|heel|skin|wound|ulcer|sore)\b[^.!?]{0,25}\b(is|are|has\s+turned|turned|looks?|going|becoming)\b[^.!?]{0,15}\b(black|blue|dark|gangren\w+|necro\w+)\b/i,
      /\bgangrene\b/i,
      /\b(pus|discharge|foul\s+smell|bad\s+smell|smelly)\b[^.!?]{0,50}\b(foot|feet|toe|heel|wound|ulcer|sore)\b/i,
      // Reverse order: the site is named first, the sign second.
      /\b(foot|feet|toe|toes|heel|wound|ulcer|sore)\b[^.!?]{0,50}\b(pus|foul\s+smell|bad\s+smell|smelly|spreading|red\s+streak)\b/i,
      /(পা|পায়ে|আঙুল)[^।.!?]{0,40}(কালো|পচে|পুঁজ|দুর্গন্ধ|ঘা)/,
      /(पैर|पाँव|उंगली)[^।.!?]{0,40}(काला|सड़|मवाद|बदबू|घाव)/,
    ],
  },
  {
    id: 'RF_FOOT_WOUND',
    label: 'Diabetic foot wound reported',
    urgency: 'urgent',
    alertType: 'foot_infection',
    patterns: [
      /\b(wound|ulcer|sore|cut|blister|injury|infection)\b[^.!?]{0,40}\b(foot|feet|toe|heel|sole)\b/i,
      /\b(foot|feet|toe|heel)\b[^.!?]{0,40}\b(wound|ulcer|sore|cut|blister|swollen|red|infected)\b/i,
      /(পা|পায়ে|পায়ের|আঙুলে)[^।.!?]{0,30}(ঘা|ক্ষত|কাটা|ফোস্কা|ফুলে|লাল)/,
      /(पैर|पाँव|पांव|उंगली|एड़ी)[^।.!?]{0,30}(घाव|ज़ख्म|जख्म|कट|छाला|सूजन|लाल)/,
    ],
  },
  {
    id: 'RF_MISSED_INSULIN',
    label: 'Missed insulin or medication dose',
    urgency: 'advice',
    alertType: 'medication_nonadherence',
    patterns: [
      /\b(forgot|missed|skipped|did\s*n[o']?t\s+take)\b[^.!?]{0,40}\b(insulin|injection|dose|medicine|medication|tablet|pill)\b/i,
      /\b(insulin|medicine|tablet)\b[^.!?]{0,30}\b(forgot|missed|skipped)\b/i,
      /(ইনসুলিন|ওষুধ|ট্যাবলেট)[^।.!?]{0,30}(ভুলে|নিতে\s*ভুলে|মিস|খাইনি|নিইনি)/,
      /(इंसुलिन|दवा|दवाई|गोली)[^।.!?]{0,30}(भूल|मिस|नहीं\s*ली|नहीं\s*लिया)/,
    ],
  },
  {
    id: 'RF_MED_SIDE_EFFECT',
    label: 'Adverse reaction after medication',
    urgency: 'urgent',
    alertType: 'other',
    patterns: [
      /\b(dizzy|dizziness|nausea|vomit\w*|rash|swelling|itching|weak)\b[^.!?]{0,50}\b(after|since)\b[^.!?]{0,30}\b(medicine|medication|tablet|insulin|dose|pill)\b/i,
      /\b(after|since)\s+(taking|starting)\b[^.!?]{0,40}\b(dizzy|nausea|vomit\w*|rash|swelling|weak|faint)\b/i,
      /(ওষুধ|ইনসুলিন)[^।.!?]{0,30}(খাওয়ার\s*পর|নেওয়ার\s*পর)[^।.!?]{0,30}(মাথা\s*ঘোর|বমি|র‍্যাশ|দুর্বল)/,
      /(दवा|दवाई|इंसुलिन)[^।.!?]{0,30}(लेने\s*के\s*बाद)[^।.!?]{0,30}(चक्कर|उल्टी|खुजली|कमज़ोर)/,
    ],
  },
  {
    // Patients frequently report a problem qualitatively with no number
    // ("my BP is high"). That still deserves a real answer and a prompt to
    // record the actual reading, so it must not fall through as small talk.
    id: 'RF_QUALITATIVE_HIGH_BP',
    label: 'Raised blood pressure reported without a reading',
    urgency: 'advice',
    alertType: null,
    patterns: [
      /\b(blood\s*pressure|bp)\b[^.!?]{0,20}\b(is\s+)?(high|raised|elevated|up|shooting)\b/i,
      /\b(high|raised)\s+(blood\s*pressure|bp)\b/i,
      /(প্রেসার|রক্তচাপ|বিপি)[^।.!?]{0,20}(বেশি|বেড়ে|হাই|বৃদ্ধি)/,
      /(बीपी|ब्लड\s*प्रेशर|रक्तचाप)[^।.!?]{0,20}(ज्यादा|ज़्यादा|बढ़|हाई|तेज)/,
    ],
  },
  {
    id: 'RF_QUALITATIVE_ABNORMAL_SUGAR',
    label: 'Abnormal blood sugar reported without a reading',
    urgency: 'advice',
    alertType: null,
    patterns: [
      /\b(sugar|glucose)\b[^.!?]{0,20}\b(is\s+)?(very\s+)?(high|low|raised|elevated|dropping|falling)\b/i,
      /\b(high|low)\s+(blood\s*)?(sugar|glucose)\b/i,
      /(সুগার|গ্লুকোজ)[^।.!?]{0,20}(বেশি|বেড়ে|কম|কমে|হাই|লো)/,
      /(शुगर|शक्कर|ग्लूकोज)[^।.!?]{0,20}(ज्यादा|ज़्यादा|बढ़|कम|हाई|लो)/,
    ],
  },
  {
    // Statin myalgia. Not an emergency, but rhabdomyolysis is, and dark urine
    // with muscle pain is the sign that separates them.
    id: 'RF_STATIN_MYALGIA',
    label: 'Muscle pain on cholesterol medicine',
    urgency: 'urgent',
    alertType: 'other',
    patterns: [
      /\b(muscle|leg|thigh|calf|body)\s*(pain|ache|aching|cramp\w*|weakness|soreness)\b[^.!?]{0,60}\b(statin|atorvastatin|rosuvastatin|simvastatin|cholesterol\s+(medicine|tablet))\b/i,
      /\b(statin|atorvastatin|rosuvastatin|simvastatin)\b[^.!?]{0,60}\b(muscle|leg|thigh|calf)\s*(pain|ache|cramp\w*|weakness)\b/i,
      // Dark urine with muscle pain is what separates ordinary statin myalgia
      // from rhabdomyolysis, so it fires on its own. Both word orders: patients
      // write "dark urine" and "my urine has gone dark" about equally.
      /\b(dark|brown|cola[-\s]?colou?red|tea[-\s]?colou?red)\s+urine\b/i,
      /\burine\b[^.!?]{0,30}\b(dark|brown|cola[-\s]?colou?red|tea[-\s]?colou?red)\b/i,
      /(পেশি|মাংসপেশি|পায়ে)[^।.!?]{0,40}(ব্যথা|যন্ত্রণা|দুর্বল)[^।.!?]{0,40}(স্ট্যাটিন|কোলেস্টেরল)/,
      /(প্রস্রাব|পেচ্ছাপ)[^।.!?]{0,30}(কালচে|গাঢ়|বাদামি|লালচে)/,
      /(मांसपेशी|पेशी|पैर)[^।.!?]{0,40}(दर्द|कमज़ोर)[^।.!?]{0,40}(स्टेटिन|कोलेस्ट्रॉल)/,
      /(पेशाब|मूत्र)[^।.!?]{0,30}(गहरा|काला|भूरा|गाढ़ा)/,
    ],
  },
  {
    // Sudden severe joint pain — most often gout in this clinic's population,
    // but a hot swollen joint with fever can be septic arthritis, which is a
    // surgical emergency. Sent as urgent so a clinician, not the model, decides.
    id: 'RF_ACUTE_JOINT',
    label: 'Sudden severe joint pain or swelling',
    urgency: 'urgent',
    alertType: 'other',
    patterns: [
      /\b(sudden|severe|terrible|unbearable)\b[^.!?]{0,30}\b(joint|toe|ankle|knee|wrist)\b[^.!?]{0,30}\b(pain|swell\w+|red|hot)\b/i,
      /\b(big\s+toe|great\s+toe)\b[^.!?]{0,40}\b(pain|swollen|swelling|red|hot)\b/i,
      /\bgout\s*(attack|flare)\b/i,
      /(হঠাৎ)[^।.!?]{0,30}(গাঁট|জয়েন্ট|বুড়ো\s*আঙুল|হাঁটু)[^।.!?]{0,30}(ব্যথা|ফুলে|লাল)/,
      /(अचानक)[^।.!?]{0,30}(जोड़|अंगूठ|घुटन|टखन)[^।.!?]{0,30}(दर्द|सूजन|लाल)/,
    ],
  },
  {
    // Hypoglycaemia unawareness. Losing warning symptoms is a recognised
    // indication to relax targets — a prescribing decision, so it escalates
    // to the doctor rather than being answered by the assistant.
    id: 'RF_HYPO_UNAWARENESS',
    label: 'Loss of hypoglycaemia warning symptoms',
    urgency: 'urgent',
    alertType: 'severe_hypoglycaemia',
    patterns: [
      /\b(no|without|don'?t\s+get|do\s+not\s+get|lost|losing)\s+(any\s+)?(warning|symptoms?|signs?)\b[^.!?]{0,40}\b(low|hypo|sugar)\b/i,
      /\b(can(no|')?t|don'?t)\s+(feel|tell|sense)\b[^.!?]{0,30}\b(when|if)\b[^.!?]{0,20}\b(sugar|low|hypo)\b/i,
      /\b(hypo|low)\b[^.!?]{0,30}\bwithout\s+(any\s+)?warning\b/i,
      /(সুগার\s*কমে\s*গেলে)[^।.!?]{0,40}(বুঝতে\s*পারি\s*না|টের\s*পাই\s*না)/,
      /(शुगर\s*कम\s*होने)[^।.!?]{0,40}(पता\s*नहीं\s*चलता|महसूस\s*नहीं)/,
    ],
  },
  {
    // Diabetes distress and depression are both common and under-reported.
    // Below self-harm on the ladder, but must never be answered as small talk.
    id: 'RF_MOOD_DISTRESS',
    label: 'Low mood or diabetes distress',
    urgency: 'advice',
    alertType: null,
    patterns: [
      /\b(depress\w+|hopeless|worthless|giving\s+up|can(no|')?t\s+cope|burnt?\s*out|exhausted\s+by)\b/i,
      /\b(tired|sick|fed\s*up)\s+of\s+(this\s+)?(diabetes|injections|pricking|medicines)\b/i,
      /\b(anxious|anxiety|panic|worried\s+all\s+the\s+time)\b/i,
      /(হতাশ|মনমরা|আর\s*পারছি\s*না|দুশ্চিন্তা|উদ্বেগ)/,
      /(निराश|उदास|हिम्मत\s*नहीं|घबराहट|चिंता\s*बहुत)/,
    ],
  },
  {
    id: 'RF_SUICIDAL',
    label: 'Self-harm risk',
    urgency: 'emergency',
    alertType: 'other',
    patterns: [
      /\b(kill\s+myself|end\s+my\s+life|suicid\w+|don'?t\s+want\s+to\s+live|better\s+off\s+dead)\b/i,
      /\b(overdose)\b[^.!?]{0,30}\b(myself|on\s+purpose|intentional)/i,
      /(আত্মহত্যা|মরে\s*যেতে\s*চাই|বাঁচতে\s*চাই\s*না)/,
      /(आत्महत्या|खुदकुशी|मरना\s*चाहता|जीना\s*नहीं\s*चाहता)/,
    ],
  },
]);

/**
 * @param {string} text raw patient message
 * @returns {Array<{id:string,label:string,urgency:string,alertType:string}>}
 */
export function matchRedFlags(text) {
  if (!text || typeof text !== 'string') return [];
  const normalised = text.normalize('NFC');
  const hits = [];
  for (const rule of RED_FLAG_RULES) {
    if (rule.patterns.some((re) => re.test(normalised))) {
      hits.push({
        id: rule.id,
        label: rule.label,
        urgency: rule.urgency,
        alertType: rule.alertType,
      });
    }
  }
  return hits;
}
