import './style.css';
import { createIcons, ArrowUpRight, Download, MapPin, Sparkles, TrendingUp, MonitorCog, UsersRound, Handshake, FileCheck2, ChartNoAxesCombined, MessagesSquare, GraduationCap, Mail, MessageCircle, Linkedin, ArrowUp, Menu, X, ChevronDown } from 'lucide';
const icons = { ArrowUpRight, Download, MapPin, Sparkles, TrendingUp, MonitorCog, UsersRound, Handshake, FileCheck2, ChartNoAxesCombined, MessagesSquare, GraduationCap, Mail, MessageCircle, Linkedin, ArrowUp, Menu, X, ChevronDown };
const jobs = [
 {period:'Mei 2023 — Juni 2026',company:'PT. Wismilak Inti Makmur Tbk',role:'Retail Trade Salesman',initial:'W',type:'sales',category:'Sales & Distribution',details:['Mengelola distribusi produk retail untuk memastikan ketersediaan dan visibilitas produk di outlet.','Membangun hubungan bisnis dengan ratusan pemilik toko dan retailer untuk menjaga pertumbuhan pasar.','Mencapai target penjualan bulanan melalui strategi kunjungan yang efektif dan pemantauan stok.','Menganalisis kompetitor dan tren pasar sebagai masukan strategis bagi tim pemasaran.']},
 {period:'Juni 2022 — Apr 2023',company:'PT. Sinar Sosro',role:'Sales Supervisor',initial:'S',type:'sales',category:'Sales & Leadership',details:['Memimpin dan memotivasi tim sales untuk mencapai target tahunan di wilayah KP. PSP.','Mengelola stok mitra agar ketersediaan produk di pasar tetap stabil.','Mengembangkan area penjualan baru melalui pemetaan outlet.','Menyelesaikan masalah operasional lapangan untuk menjaga produktivitas tim.']},
 {period:'2021 — 2022',company:'CV. Mitra Cahaya Nauli',role:'Sales Taking Order · Sibolga',initial:'M',type:'sales',category:'Sales & Relationship',details:['Mengelola hubungan dengan outlet yang sudah ada serta mengakuisisi outlet baru.','Memastikan pemesanan barang akurat dan proses pengiriman tepat waktu.']},
 {period:'2019 — 2020',company:'PT. CNS SBO (Mayora)',role:'Sales Canvas · Siborong-Borong',initial:'C',type:'sales',category:'Sales & Expansion',details:['Melakukan penetrasi pasar secara langsung untuk meningkatkan volume penjualan produk.','Menganalisis kebutuhan pelanggan di lapangan untuk mengoptimalkan strategi penjualan harian.']},
 {period:'2013 — 2017',company:'Ganesha Operation',role:'IT Staff · Sibolga',initial:'G',type:'it',category:'IT & Technical Support',details:['Memelihara dan memperbaiki perangkat keras serta infrastruktur jaringan komputer.','Mengelola perangkat virtual dan menjaga kelancaran operasional sistem internal.','Mendukung aktivitas marketing online melalui optimasi perangkat dan platform digital.']},
 {period:'2012 — 2013',company:'METRO Credit/Cash',role:'Collector · Sibolga',initial:'M',type:'sales',category:'Customer Relations',details:['Mengelola penagihan angsuran kredit barang.','Menangani akun tertunda dengan pendekatan komunikasi yang persuasif.']},
];
const list = document.querySelector('#experience-list');
function renderJobs(filter = 'all') {
 list.innerHTML = jobs.map((job, i) => ({job,i})).filter(({job}) => filter === 'all' || job.type === filter).map(({job,i}) => `<article class="job ${i === 0 ? 'open' : ''}"><button class="job-summary" aria-expanded="${i === 0}" aria-controls="job-${i}"><span class="job-period">${job.period}</span><span class="job-logo" aria-hidden="true">${job.initial}</span><div class="job-title"><h3>${job.company}</h3><p>${job.role}</p></div><div class="job-end"><span class="job-category">${job.category}</span><i data-lucide="chevron-down"></i></div></button><div class="job-details" id="job-${i}" ${i === 0 ? '' : 'hidden'}><ul>${job.details.map(d=>`<li>${d}</li>`).join('')}</ul></div></article>`).join('');
 createIcons({icons});
}
renderJobs();
list.addEventListener('click', e => {
 const button = e.target.closest('.job-summary');
 if (!button) return;
 const expanded = button.getAttribute('aria-expanded') === 'true';
 button.setAttribute('aria-expanded', String(!expanded));
 button.closest('.job').classList.toggle('open', !expanded);
 document.getElementById(button.getAttribute('aria-controls')).hidden = expanded;
});
document.querySelectorAll('[data-filter]').forEach(button => button.addEventListener('click', () => {
 document.querySelectorAll('[data-filter]').forEach(b => {b.classList.toggle('selected', b === button); b.setAttribute('aria-pressed', String(b === button));});
 renderJobs(button.dataset.filter);
}));
const toggle = document.querySelector('.menu-toggle');
const nav = document.querySelector('nav');
function setMenu(open) {
 nav.classList.toggle('visible', open);
 toggle.setAttribute('aria-expanded', String(open));
 toggle.setAttribute('aria-label', open ? 'Tutup navigasi' : 'Buka navigasi');
 toggle.innerHTML = `<i data-lucide="${open ? 'x' : 'menu'}"></i>`;
 createIcons({icons});
}
toggle.addEventListener('click', () => setMenu(toggle.getAttribute('aria-expanded') !== 'true'));
nav.querySelectorAll('a').forEach(a => a.addEventListener('click', () => setMenu(false)));
document.addEventListener('keydown', e => {if(e.key === 'Escape') setMenu(false);});
const sections = [...document.querySelectorAll('section[id]')];
const observer = new IntersectionObserver(entries => {
 for (const entry of entries) if (entry.isIntersecting) nav.querySelectorAll('a').forEach(link => link.classList.toggle('active', link.hash === '#' + entry.target.id));
}, {rootMargin:'-15% 0px -65% 0px',threshold:0});
sections.forEach(s => observer.observe(s));
document.querySelector('#year').textContent = new Date().getFullYear();
