# -*- coding: utf-8 -*-
"""Menguji perintah SQL baru pada lib/kasir_lokal.dart memakai SQLite asli."""
import sqlite3

d = sqlite3.connect(':memory:')
d.executescript('''
CREATE TABLE toko (
  id_customer TEXT PRIMARY KEY,
  nama TEXT NOT NULL DEFAULT '',
  alamat TEXT NOT NULL DEFAULT '',
  district TEXT NOT NULL DEFAULT '',
  salesman TEXT NOT NULL DEFAULT '',
  hp TEXT NOT NULL DEFAULT '',
  tipe TEXT NOT NULL DEFAULT 'REGULER',
  latitude TEXT NOT NULL DEFAULT '',
  longitude TEXT NOT NULL DEFAULT '',
  kunjungan TEXT NOT NULL DEFAULT '',
  hari TEXT NOT NULL DEFAULT '',
  diperbarui TEXT NOT NULL DEFAULT ''
);
CREATE TABLE program_input (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  jenis TEXT NOT NULL DEFAULT '',
  paket TEXT NOT NULL DEFAULT '',
  id_customer TEXT NOT NULL DEFAULT '',
  nama_toko TEXT NOT NULL DEFAULT '',
  jumlah REAL NOT NULL DEFAULT 0,
  tanggal TEXT NOT NULL DEFAULT '',
  kirim INTEGER NOT NULL DEFAULT 0,
  id_sales TEXT NOT NULL DEFAULT ''
);
''')

toko = [
    ('C-1', 'AL HIJRAH JAYA', 'JL A', 'MEDAN KOTA', 'RTS 1', '0811', 'REGULER', '3.59', '98.67', 'Weekly', 'Senin', ''),
    ('C-2', 'ADEK ABANG', 'JL B', 'MEDAN KOTA', 'RTS 1', '0812', 'REGULER', '3.60', '98.68', 'Bi-Weekly Ganjil', 'Selasa', ''),
    ('C-3', 'TOKO TIGA', 'JL C', 'BINJAI', 'RTS 2', '0813', 'REGULER', '', '', 'Weekly', 'Rabu', ''),
    ('C-4', 'TOKO EMPAT', 'JL D', 'BINJAI', 'RTS 2', '0814', 'GSP', '3.61', '98.69', 'Weekly', 'Selasa', ''),
    ('C-5', 'TOKO LIMA', 'JL E', '', 'RTS 3', '0815', 'REGULER', '3.62', '98.70', '', 'Senin', ''),
]
d.executemany('INSERT INTO toko (id_customer,nama,alamat,district,salesman,hp,tipe,latitude,longitude,kunjungan,hari,diperbarui) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', toko)

program = [
    ('INTRODEAL', '1+1', 'C-1', 'AL HIJRAH JAYA', 1, '2026-10-05', 0, 'sales1'),
    ('INTRODEAL', '1+1', 'C-2', 'ADEK ABANG', 1, '2026-10-05', 1, 'sales1'),
    ('BD', '', 'C-4', 'TOKO EMPAT', 0, '2026-10-04', 0, 'sales1'),
    ('PROGRAM GAWIH', '', 'C-5', 'TOKO LIMA', 0, '2026-10-04', 0, 'sales1'),
    ('INTRODEAL', '1+1', 'C-9', 'TOKO TANPA DATA', 0, '2026-10-03', 0, 'sales1'),
    ('INTRODEAL', '1+1', 'C-1', 'AL HIJRAH JAYA', 1, '2026-10-03', 0, 'sales2'),
]
d.executemany('INSERT INTO program_input (jenis,paket,id_customer,nama_toko,jumlah,tanggal,kirim,id_sales) VALUES (?,?,?,?,?,?,?,?)', program)
d.commit()

def uji(nama, sql, args=(), harap=None):
    try:
        baris = d.execute(sql, args).fetchall()
    except Exception as e:
        print('[X] %s : GALAT SQL -> %s' % (nama, e))
        return
    ok = True if harap is None else (len(baris) == harap)
    print('[%s] %s : %d baris %s' % ('V' if ok else 'X', nama, len(baris), '' if ok else '(harap %d)' % harap))
    for b in baris[:6]:
        print('        ', b)

# 1. _tokoDistrict
uji('toko_district: daftar district + jumlah',
    "SELECT UPPER(TRIM(COALESCE(district, ''))) AS district, COUNT(*) AS jumlah "
    "FROM toko GROUP BY UPPER(TRIM(COALESCE(district, ''))) "
    "ORDER BY jumlah DESC, district ASC", (), 3)

# 2. _tokoPeta per district
uji('toko_peta: penyaring district MEDAN KOTA',
    "SELECT id_customer FROM toko WHERE UPPER(TRIM(district)) = ? ORDER BY nama ASC LIMIT 5000",
    ('MEDAN KOTA',), 2)

# 3. _tokoPeta satu toko
uji('toko_peta: satu toko (id_customer)',
    "SELECT id_customer FROM toko WHERE id_customer = ? ORDER BY nama ASC LIMIT 1",
    ('C-3',), 1)

# 4. _tokoDaftar: cari + district
uji('toko_daftar: cari + district',
    "SELECT id_customer FROM toko WHERE (nama LIKE ? OR id_customer LIKE ? OR alamat LIKE ?) "
    "AND UPPER(TRIM(district)) = ? ORDER BY nama ASC LIMIT 300",
    ('%TOKO%', '%TOKO%', '%TOKO%', 'BINJAI'), 2)

# 5. _programCustomerDaftar dengan JOIN + district
sql_program = ('SELECT p.*, '
               "COALESCE(t.district, '') AS district_toko, "
               "COALESCE(t.hari, '') AS hari_toko, "
               "COALESCE(t.kunjungan, '') AS kunjungan_toko "
               'FROM program_input p LEFT JOIN toko t ON t.id_customer = p.id_customer '
               'WHERE p.id_sales = ? AND p.jenis = ? AND UPPER(TRIM(COALESCE(t.district, \'\'))) = ? '
               'ORDER BY p.id DESC LIMIT ?')
baris = d.execute(sql_program, ('sales1', 'INTRODEAL', 'MEDAN KOTA', 300)).fetchall()
print('[%s] program_customer_daftar: JOIN + district -> %d baris, hari=%s' % (
    'V' if len(baris) == 2 else 'X', len(baris), [b[9] for b in baris]))

kosong = d.execute(sql_program, ('sales1', 'BD', 'MEDAN KOTA', 300)).fetchall()
print('[%s] program_customer_daftar: BD di district lain -> %d baris' % ('V' if not kosong else 'X', len(kosong)))

# 6. program_input tanpa toko (toko belum ada di salinan HP) tetap terbaca? 
tanpa = d.execute(sql_program, ('sales1', 'PROGRAM GAWIH', '', 300)).fetchall()
print('[%s] program_customer_daftar: program buatan sendiri (tanpa district) -> %d baris, district=%s' % (
    'V' if len(tanpa) == 1 else 'X', len(tanpa), tanpa[0][8] if tanpa else '-'))

# 7. versi tanpa district (SEMUA DISTRICT)
semua = d.execute(sql_program.rsplit(' AND UPPER', 1)[0] + ' ORDER BY p.id DESC LIMIT ?',
                  ('sales1', 'INTRODEAL', 300)).fetchall()
print('[%s] program_customer_daftar: SEMUA district -> %d baris (C-1, C-2, dan C-9 tanpa data toko)' % ('V' if len(semua) == 3 else 'X', len(semua)))
print('     (C-1 sales1, C-2 sales1 => 2; milik sales2 tidak ikut)')
print('SELESAI')
