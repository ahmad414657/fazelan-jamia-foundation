#!/usr/bin/env bash
set -e

echo "=========================================="
echo " ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন - ধাপ ১ সেটআপ"
echo "=========================================="

# ১. PostgreSQL ও PHP pdo_pgsql এক্সটেনশন সেটআপ
echo "[1/6] PostgreSQL এবং PHP ড্রাইভার প্রস্তুত করা হচ্ছে..."
sudo apt-get update -y
sudo apt-get install -y libpq-dev postgresql postgresql-contrib

if ! php -m | grep -qi "pdo_pgsql"; then
  sudo docker-php-ext-install pdo_pgsql pgsql
fi

sudo service postgresql start
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='fjp_admin'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER fjp_admin WITH PASSWORD 'fjp_secret_pass';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='fazelan_jamia'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE fazelan_jamia OWNER fjp_admin;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE fazelan_jamia TO fjp_admin;"

# ২. Laravel ব্যাকএন্ড তৈরি
echo "[2/6] Laravel ব্যাকএন্ড ইনস্টল করা হচ্ছে..."
if [ ! -d "backend" ]; then
  composer create-project laravel/laravel backend --no-interaction
fi

cd backend
php artisan install:api --no-interaction || true
php artisan config:publish cors --no-interaction || true

# .env ফাইলে PostgreSQL কনফিগারেশন
sed -i 's/^DB_CONNECTION=.*/DB_CONNECTION=pgsql/' .env
sed -i 's/^#\? *DB_HOST=.*/DB_HOST=127.0.0.1/' .env
sed -i 's/^#\? *DB_PORT=.*/DB_PORT=5432/' .env
sed -i 's/^#\? *DB_DATABASE=.*/DB_DATABASE=fazelan_jamia/' .env
sed -i 's/^#\? *DB_USERNAME=.*/DB_USERNAME=fjp_admin/' .env
sed -i 's/^#\? *DB_PASSWORD=.*/DB_PASSWORD=fjp_secret_pass/' .env

# ৩. ডেটাবেজ মাইগ্রেশন (৪৯টি ফিল্ড ও রিলেশনাল টেবিল)
echo "[3/6] PostgreSQL ডেটাবেজ স্কিমা তৈরি করা হচ্ছে..."
cat << 'EOF' > database/migrations/2026_01_01_000001_create_members_tables.php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('members', function (Blueprint $table) {
            $table->id();
            $table->uuid('uuid')->unique();
            $table->string('registration_number', 32)->unique();

            $table->enum('identity_language', ['bn', 'en', 'ar'])->default('bn');
            $table->string('full_name', 200);
            $table->string('father_name', 200);
            $table->string('guardian_name', 200)->nullable();
            $table->date('date_of_birth');
            $table->string('nid_number', 30)->nullable()->index();
            $table->string('birth_reg_number', 30)->nullable()->index();
            $table->string('passport_number', 30)->nullable()->index();
            $table->string('identity_fingerprint', 64)->nullable()->index();

            $table->date('submission_date');
            $table->string('signature_path', 500)->nullable();
            $table->enum('signature_type', ['upload', 'digital_draw'])->default('upload');

            $table->enum('status', ['pending', 'approved', 'rejected'])->default('pending')->index();
            $table->text('admin_remarks')->nullable();
            $table->foreignId('reviewed_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->string('submitted_ip', 45)->nullable();

            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('member_addresses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('member_id')->constrained('members')->cascadeOnDelete();
            $table->enum('address_type', ['permanent', 'present']);
            $table->string('village_housing', 255);
            $table->string('ward_no', 50)->nullable();
            $table->string('post_office', 150);
            $table->string('thana', 150);
            $table->string('district', 150)->index();
            $table->string('division', 150)->index();
            $table->string('country', 150)->default('Bangladesh')->index();
            $table->timestamps();
            $table->unique(['member_id', 'address_type']);
        });

        Schema::create('member_contacts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('member_id')->unique()->constrained('members')->cascadeOnDelete();
            $table->string('mobile_number', 30)->index();
            $table->string('whatsapp_imo', 30)->nullable();
            $table->string('facebook', 255)->nullable();
            $table->string('email', 200)->nullable()->index();
            $table->timestamps();
        });

        Schema::create('member_education_professions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('member_id')->unique()->constrained('members')->cascadeOnDelete();
            $table->string('educational_qualification', 200)->index();
            $table->string('profession', 200)->index();
            $table->string('workplace', 255)->nullable();
            $table->string('workplace_thana', 150)->nullable();
            $table->string('workplace_district', 150)->nullable();
            $table->string('workplace_country', 150)->nullable();
            $table->string('workplace_city', 150)->nullable();
            $table->string('workplace_mobile', 30)->nullable();
            $table->boolean('has_dawra_hadith')->default(false)->index();
            $table->boolean('has_takhassus')->default(false)->index();
            $table->boolean('has_hifz')->default(false)->index();
            $table->string('takhassus_type', 200)->nullable()->index();
            $table->string('dawra_hijri_year', 20)->nullable()->index();
            $table->string('dawra_gregorian_year', 20)->nullable()->index();
            $table->string('takhassus_hijri_year', 20)->nullable()->index();
            $table->string('takhassus_gregorian_year', 20)->nullable()->index();
            $table->string('hifz_hijri_year', 20)->nullable()->index();
            $table->string('hifz_gregorian_year', 20)->nullable()->index();
            $table->timestamps();
        });

        Schema::create('member_payments_documents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('member_id')->unique()->constrained('members')->cascadeOnDelete();
            $table->string('fee_payment_method', 100);
            $table->string('nid_passport_path', 500)->nullable();
            $table->string('nid_passport_mime', 100)->nullable();
            $table->unsignedBigInteger('nid_passport_size')->nullable();
            $table->string('photo_path', 500)->nullable();
            $table->string('photo_mime', 100)->nullable();
            $table->unsignedBigInteger('photo_size')->nullable();
            $table->string('money_receipt_path', 500)->nullable();
            $table->string('money_receipt_mime', 100)->nullable();
            $table->unsignedBigInteger('money_receipt_size')->nullable();
            $table->timestamps();
        });

        Schema::create('form_field_settings', function (Blueprint $table) {
            $table->id();
            $table->unsignedSmallInteger('field_number')->unique();
            $table->string('field_key', 100)->unique();
            $table->string('section_key', 50);
            $table->boolean('is_required')->default(true);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('admin_activity_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('action', 100);
            $table->string('target_type', 100)->nullable();
            $table->unsignedBigInteger('target_id')->nullable();
            $table->jsonb('metadata')->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('admin_activity_logs');
        Schema::dropIfExists('form_field_settings');
        Schema::dropIfExists('member_payments_documents');
        Schema::dropIfExists('member_education_professions');
        Schema::dropIfExists('member_contacts');
        Schema::dropIfExists('member_addresses');
        Schema::dropIfExists('members');
    }
};
EOF

# ৪৯টি ফিল্ডের সেটিংস সিডার
cat << 'EOF' > database/seeders/FormFieldSettingsSeeder.php
<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class FormFieldSettingsSeeder extends Seeder
{
    public function run(): void
    {
        $fields = [
            [1, 'identity_language', 's1', true],
            [2, 'full_name', 's1', true],
            [3, 'father_name', 's1', true],
            [4, 'guardian_name', 's1', false],
            [5, 'date_of_birth', 's1', true],
            [6, 'nid_number', 's1', false],
            [7, 'birth_reg_number', 's1', false],
            [8, 'passport_number', 's1', false],
            [9, 'perm_village_housing', 's2', true],
            [10, 'perm_ward_no', 's2', false],
            [11, 'perm_post_office', 's2', true],
            [12, 'perm_thana', 's2', true],
            [13, 'perm_district', 's2', true],
            [14, 'perm_division', 's2', true],
            [15, 'perm_country', 's2', true],
            [16, 'pres_village_housing', 's3', true],
            [17, 'pres_post_office', 's3', true],
            [18, 'pres_thana', 's3', true],
            [19, 'pres_district', 's3', true],
            [20, 'pres_division', 's3', true],
            [21, 'pres_country', 's3', true],
            [22, 'contact_mobile', 's4', true],
            [23, 'whatsapp_imo', 's4', false],
            [24, 'facebook', 's4', false],
            [25, 'email', 's4', false],
            [26, 'educational_qualification', 's5', true],
            [27, 'profession', 's5', true],
            [28, 'workplace', 's5', false],
            [29, 'workplace_thana', 's5', false],
            [30, 'workplace_district', 's5', false],
            [31, 'workplace_country', 's5', false],
            [32, 'workplace_city', 's5', false],
            [33, 'workplace_mobile', 's5', false],
            [34, 'has_dawra_hadith', 's6', false],
            [35, 'has_takhassus', 's6', false],
            [36, 'has_hifz', 's6', false],
            [37, 'takhassus_type', 's6', false],
            [38, 'dawra_hijri_year', 's7', false],
            [39, 'dawra_gregorian_year', 's7', false],
            [40, 'takhassus_hijri_year', 's7', false],
            [41, 'takhassus_gregorian_year', 's7', false],
            [42, 'hifz_hijri_year', 's7', false],
            [43, 'hifz_gregorian_year', 's7', false],
            [44, 'fee_payment_method', 's8', true],
            [45, 'nid_passport_file', 's8', true],
            [46, 'photo_file', 's8', true],
            [47, 'money_receipt_file', 's8', true],
            [48, 'submission_date', 's9', true],
            [49, 'signature', 's9', true],
        ];

        foreach ($fields as [$num, $key, $sec, $req]) {
            DB::table('form_field_settings')->updateOrInsert(
                ['field_number' => $num],
                [
                    'field_key' => $key,
                    'section_key' => $sec,
                    'is_required' => $req,
                    'is_active' => true,
                    'updated_at' => now(),
                    'created_at' => now(),
                ]
            );
        }
    }
}
EOF

# Health & Field-settings পাবলিক API রাউট
cat << 'EOF' >> routes/api.php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    try {
        DB::connection()->getPdo();
        return response()->json([
            'status' => 'ok',
            'database' => 'connected',
            'app' => 'Fazelan-e Jamia Foundation API',
        ]);
    } catch (\Throwable $e) {
        return response()->json(['status' => 'error'], 500);
    }
});

Route::get('/public/form-settings', function () {
    return response()->json([
        'fields' => DB::table('form_field_settings')->orderBy('field_number')->get(),
    ]);
});
EOF

php artisan migrate --force
php artisan db:seed --class=FormFieldSettingsSeeder --force
cd ..

# ৪. Next.js ফ্রন্টএন্ড তৈরি
echo "[4/6] Next.js (TypeScript + Tailwind CSS) ইনস্টল করা হচ্ছে..."
if [ ! -d "frontend" ]; then
  npx create-next-app@latest frontend --use-npm --typescript --eslint --tailwind --src-dir --app --import-alias "@/*" --no-git --yes
fi

mkdir -p frontend/src/locales frontend/src/context frontend/src/components/layout

echo "[5/6] ৩ ভাষার ডিকশনারি ও হোমপেজ ফাইল লেখা হচ্ছে..."

cat << 'EOF' > frontend/src/locales/types.ts
export type Locale = 'bn' | 'en' | 'ar';

export interface TranslationDictionary {
  meta: {
    dir: 'ltr' | 'rtl';
    langName: string;
    foundationName: string;
    shortTagline: string;
  };
  nav: {
    home: string;
    about: string;
    purpose: string;
    guidelines: string;
    contact: string;
    registerBtn: string;
    adminLogin: string;
  };
  home: {
    heroBadge: string;
    heroTitle: string;
    heroSubtitle: string;
    registerNow: string;
    learnMore: string;
    introTitle: string;
    introBody: string;
    aboutTitle: string;
    aboutBody: string;
    purposeTitle: string;
    purposePoints: string[];
    guidelinesTitle: string;
    guidelinesSteps: string[];
    contactTitle: string;
    contactSubtitle: string;
    officeAddressLabel: string;
    officeAddress: string;
    phoneLabel: string;
    emailLabel: string;
    footerCopyright: string;
  };
  formSections: {
    s1: string;
    s2: string;
    s3: string;
    s4: string;
    s5: string;
    s6: string;
    s7: string;
    s8: string;
    s9: string;
    copyPermanentAddress: string;
  };
  fields49: {
    f01_identity_language: string;
    f02_name: string;
    f03_father: string;
    f04_guardian: string;
    f05_date_of_birth: string;
    f06_nid_number: string;
    f07_birth_reg_number: string;
    f08_passport_number: string;
    f09_perm_village_housing: string;
    f10_perm_ward_no: string;
    f11_perm_post_office: string;
    f12_perm_thana: string;
    f13_perm_district: string;
    f14_perm_division: string;
    f15_perm_country: string;
    f16_pres_village_housing: string;
    f17_pres_post_office: string;
    f18_pres_thana: string;
    f19_pres_district: string;
    f20_pres_division: string;
    f21_pres_country: string;
    f22_contact_mobile: string;
    f23_whatsapp_imo: string;
    f24_facebook: string;
    f25_email: string;
    f26_educational_qualification: string;
    f27_profession: string;
    f28_workplace: string;
    f29_workplace_thana: string;
    f30_workplace_district: string;
    f31_workplace_country: string;
    f32_workplace_city: string;
    f33_workplace_mobile: string;
    f34_dawra_hadith: string;
    f35_takhassus: string;
    f36_hifz: string;
    f37_takhassus_type: string;
    f38_dawra_hijri_year: string;
    f39_dawra_gregorian_year: string;
    f40_takhassus_hijri_year: string;
    f41_takhassus_gregorian_year: string;
    f42_hifz_hijri_year: string;
    f43_hifz_gregorian_year: string;
    f44_fee_payment_method: string;
    f45_nid_passport_file: string;
    f46_photo_file: string;
    f47_money_receipt_file: string;
    f48_date: string;
    f49_signature: string;
  };
}
EOF

cat << 'EOF' > frontend/src/locales/bn.ts
import { TranslationDictionary } from './types';

export const bn: TranslationDictionary = {
  meta: {
    dir: 'ltr',
    langName: 'বাংলা',
    foundationName: 'ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন',
    shortTagline: 'প্রাক্তন শিক্ষার্থীদের ঐক্য, সেবা ও তথ্য ব্যবস্থাপনা প্ল্যাটফর্ম',
  },
  nav: {
    home: 'হোম',
    about: 'ফাউন্ডেশন সম্পর্কে',
    purpose: 'উদ্দেশ্য',
    guidelines: 'নির্দেশনা',
    contact: 'যোগাযোগ',
    registerBtn: 'অনলাইন নিবন্ধন',
    adminLogin: 'অ্যাডমিন প্যানেল',
  },
  home: {
    heroBadge: 'অফিশিয়াল সদস্য নিবন্ধন পোর্টাল',
    heroTitle: 'ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন',
    heroSubtitle:
      'জামিয়া পটিয়ার ফাজেল ও প্রাক্তন শিক্ষার্থীদের সুসংগঠিত ডেটাবেজ, পারস্পরিক যোগাযোগ এবং কল্যাণমূলক কার্যক্রম পরিচালনার জন্য একটি নিরাপদ ও বহুভাষিক ডিজিটাল প্ল্যাটফর্ম।',
    registerNow: 'অনলাইন নিবন্ধন করুন',
    learnMore: 'নিবন্ধন নির্দেশনা দেখুন',
    introTitle: 'ফাউন্ডেশনের পরিচিতি',
    introBody:
      '“ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন” দেশে ও বিদেশে অবস্থানরত জামিয়া ইসলামিয়া পটিয়ার ফাজেল, মুহাদ্দিস, মুফতি, হাফেজ ও প্রাক্তন শিক্ষার্থীদের একটি সমন্বিত ও সেবামূলক প্ল্যাটফর্ম।',
    aboutTitle: 'ফাউন্ডেশন সম্পর্কে',
    aboutBody:
      'বিশ্বের বিভিন্ন প্রান্তে কর্মরত ও অবস্থানরত জামিয়া পটিয়ার সন্তানদের একই ছাতার নিচে ঐক্যবদ্ধ করা, শিক্ষা-গবেষণা ও সামাজিক কল্যাণমূলক কাজে অংশগ্রহণ নিশ্চিত করা এবং একটি যাচাইকৃত সদস্য ডাটাবেজ সংরক্ষণ করাই এই ফাউন্ডেশনের মূল লক্ষ্য।',
    purposeTitle: 'নিবন্ধনের উদ্দেশ্য',
    purposePoints: [
      'দেশ-বিদেশের সকল ফাজেল ও প্রাক্তন শিক্ষার্থীর নির্ভুল তথ্য সংরক্ষণ।',
      'দাওরায়ে হাদীস, তাখাসসুস ও হিফজ সমাপনকারীদের বছরভিত্তিক ও বিভাগভিত্তিক তালিকা প্রস্তুত।',
      'পেশা ও কর্মস্থল অনুযায়ী পারস্পরিক সহযোগিতা ও নেটওয়ার্কিং গড়ে তোলা।',
      'ভবিষ্যৎ সামাজিক, শিক্ষামূলক ও কল্যাণ প্রকল্পে দ্রুত যোগাযোগ ও সমন্বয়।',
    ],
    guidelinesTitle: 'নিবন্ধন সংক্রান্ত নির্দেশনা',
    guidelinesSteps: [
      'নিবন্ধনের জন্য কোনো অ্যাকাউন্ট তৈরি বা লগইন করার প্রয়োজন নেই। সরাসরি “অনলাইন নিবন্ধন” বাটনে ক্লিক করুন।',
      'প্রথম বিভাগে আপনার পছন্দের পরিচিতির ভাষা (বাংলা, ইংরেজি বা আরবি) নির্বাচন করুন এবং ব্যক্তিগত তথ্য সঠিকভাবে পূরণ করুন।',
      'স্থায়ী ও বর্তমান ঠিকানা আলাদাভাবে পূরণ করুন (প্রয়োজনে “স্থায়ী ঠিকানার মতো” অপশন ব্যবহার করতে পারবেন)।',
      'NID বা পাসপোর্টের কপি, স্পষ্ট ব্যক্তিগত ছবি, টাকা জমার রসিদ এবং স্বাক্ষর আপলোড/প্রদান করুন।',
      'তথ্য জমা দেওয়ার আগে প্রিভিউ দেখে নিশ্চিত হোন এবং জমা দেওয়ার পর প্রাপ্ত ইউনিক নিবন্ধন নম্বরটি সংরক্ষণ করুন।',
    ],
    contactTitle: 'যোগাযোগের তথ্য',
    contactSubtitle: 'নিবন্ধন বা তথ্য সংশোধন সংক্রান্ত যেকোনো প্রয়োজনে আমাদের সাথে যোগাযোগ করুন।',
    officeAddressLabel: 'কেন্দ্রীয় কার্যালয়',
    officeAddress: 'পটিয়া, চট্টগ্রাম, বাংলাদেশ',
    phoneLabel: 'হেল্পলাইন',
    emailLabel: 'ইমেইল',
    footerCopyright: '© ২০২৬ ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন। সর্বস্বত্ব সংরক্ষিত।',
  },
  formSections: {
    s1: 'প্রথম বিভাগ: ব্যক্তিগত পরিচিতি',
    s2: 'দ্বিতীয় বিভাগ: স্থায়ী ঠিকানা',
    s3: 'তৃতীয় বিভাগ: বর্তমান ঠিকানা',
    s4: 'চতুর্থ বিভাগ: যোগাযোগের তথ্য',
    s5: 'পঞ্চম বিভাগ: শিক্ষাগত ও পেশাগত তথ্য',
    s6: 'ষষ্ঠ বিভাগ: শিক্ষাগত বিভাগ ও বিশেষায়িত শিক্ষা',
    s7: 'সপ্তম বিভাগ: শিক্ষাবর্ষ সংক্রান্ত তথ্য',
    s8: 'অষ্টম বিভাগ: ফি ও সংযুক্তি',
    s9: 'নবম বিভাগ: চূড়ান্ত তথ্য',
    copyPermanentAddress: 'স্থায়ী ঠিকানার তথ্য দিয়ে বর্তমান ঠিকানা স্বয়ংক্রিয়ভাবে পূরণ করুন',
  },
  fields49: {
    f01_identity_language: 'পরিচিতির ভাষা সিলেকশন',
    f02_name: 'নাম',
    f03_father: 'পিতা',
    f04_guardian: 'অভিভাবক',
    f05_date_of_birth: 'জন্ম সন',
    f06_nid_number: 'NID নম্বর',
    f07_birth_reg_number: 'জন্ম নিবন্ধন নম্বর',
    f08_passport_number: 'পাসপোর্ট নম্বর',
    f09_perm_village_housing: 'গ্রাম/হাউজিং নম্বর',
    f10_perm_ward_no: 'ওয়ার্ড নং',
    f11_perm_post_office: 'ডাকঘর',
    f12_perm_thana: 'থানা',
    f13_perm_district: 'জেলা',
    f14_perm_division: 'বিভাগ',
    f15_perm_country: 'দেশ',
    f16_pres_village_housing: 'গ্রাম/হাউজিং নম্বর',
    f17_pres_post_office: 'ডাকঘর',
    f18_pres_thana: 'থানা',
    f19_pres_district: 'জেলা',
    f20_pres_division: 'বিভাগ',
    f21_pres_country: 'দেশ',
    f22_contact_mobile: 'মোবাইল নম্বর',
    f23_whatsapp_imo: 'WhatsApp/Imo',
    f24_facebook: 'Facebook',
    f25_email: 'E-mail',
    f26_educational_qualification: 'শিক্ষাগত যোগ্যতা',
    f27_profession: 'পেশা',
    f28_workplace: 'কর্মস্থান',
    f29_workplace_thana: 'কর্মস্থলের থানা',
    f30_workplace_district: 'কর্মস্থলের জেলা',
    f31_workplace_country: 'দেশের নাম',
    f32_workplace_city: 'শহর',
    f33_workplace_mobile: 'মোবাইল নম্বর',
    f34_dawra_hadith: 'দাওরায়ে হাদীস',
    f35_takhassus: 'তাখাসসুস',
    f36_hifz: 'হিফজ',
    f37_takhassus_type: 'তাখাসসুসের ধরন',
    f38_dawra_hijri_year: 'দাওরায়ে হাদীস সমাপনী হিজরি সন',
    f39_dawra_gregorian_year: 'দাওরায়ে হাদীস সমাপনী খ্রিষ্টীয় সন',
    f40_takhassus_hijri_year: 'তাখাসসুস সমাপনী হিজরি সন',
    f41_takhassus_gregorian_year: 'তাখাসসুস সমাপনী খ্রিষ্টীয় সন',
    f42_hifz_hijri_year: 'হিফজ সমাপনী হিজরি সন',
    f43_hifz_gregorian_year: 'হিফজ সমাপনী খ্রিষ্টীয় সন',
    f44_fee_payment_method: 'ফি আদায়ের মাধ্যম',
    f45_nid_passport_file: 'NID/Passport',
    f46_photo_file: 'Photo',
    f47_money_receipt_file: 'Money Receipt',
    f48_date: 'তারিখ',
    f49_signature: 'স্বাক্ষর',
  },
};
EOF

cat << 'EOF' > frontend/src/locales/en.ts
import { TranslationDictionary } from './types';

export const en: TranslationDictionary = {
  meta: {
    dir: 'ltr',
    langName: 'English',
    foundationName: 'Fazelan-e Jamia Foundation',
    shortTagline: 'Alumni Unity, Welfare & Information Management Portal',
  },
  nav: {
    home: 'Home',
    about: 'About',
    purpose: 'Purpose',
    guidelines: 'Guidelines',
    contact: 'Contact',
    registerBtn: 'Online Registration',
    adminLogin: 'Admin Panel',
  },
  home: {
    heroBadge: 'Official Member Registration Portal',
    heroTitle: 'Fazelan-e Jamia Foundation',
    heroSubtitle:
      'A secure, multilingual digital platform for building a verified global directory, fostering communication, and coordinating welfare initiatives for the alumni of Jamia Patiya.',
    registerNow: 'Register Online Now',
    learnMore: 'Read Guidelines',
    introTitle: 'Introduction to the Foundation',
    introBody:
      'Fazelan-e Jamia Foundation is a unified welfare and alumni platform connecting graduates, scholars, muftis, and huffaz of Jamia Islamia Patiya residing across Bangladesh and abroad.',
    aboutTitle: 'About the Foundation',
    aboutBody:
      'Our core mission is to bring together Jamia Patiya alumni worldwide under one structured umbrella, preserve verified educational and professional records, and collaborate on educational, research, and humanitarian initiatives.',
    purposeTitle: 'Purpose of Registration',
    purposePoints: [
      'Maintain an accurate and verified directory of alumni residing locally and internationally.',
      'Organize year-wise and department-wise records of Dawra-e-Hadith, Takhassus, and Hifz graduates.',
      'Strengthen mutual cooperation and networking based on profession and workplace location.',
      'Enable rapid communication for future social, academic, and welfare programs.',
    ],
    guidelinesTitle: 'Registration Guidelines',
    guidelinesSteps: [
      'No account creation or login is required to register. Simply click the "Online Registration" button.',
      'Select your preferred identity language (Bangla, English, or Arabic) and enter accurate personal information.',
      'Fill out Permanent and Present addresses separately (or use the auto-copy option if both are the same).',
      'Upload a clear copy of your NID/Passport, personal photo, fee payment receipt, and signature.',
      'Review all details in the preview screen before submitting, and save your unique registration number.',
    ],
    contactTitle: 'Contact Information',
    contactSubtitle: 'Reach out to us for any assistance regarding registration or record updates.',
    officeAddressLabel: 'Head Office',
    officeAddress: 'Patiya, Chattogram, Bangladesh',
    phoneLabel: 'Helpline',
    emailLabel: 'E-mail',
    footerCopyright: '© 2026 Fazelan-e Jamia Foundation. All rights reserved.',
  },
  formSections: {
    s1: 'Section 1: Personal Identity',
    s2: 'Section 2: Permanent Address',
    s3: 'Section 3: Present Address',
    s4: 'Section 4: Contact Information',
    s5: 'Section 5: Educational & Professional Information',
    s6: 'Section 6: Educational Departments & Specialization',
    s7: 'Section 7: Academic Completion Years',
    s8: 'Section 8: Fee & Attachments',
    s9: 'Section 9: Final Information',
    copyPermanentAddress: 'Auto-fill Present Address from Permanent Address',
  },
  fields49: {
    f01_identity_language: 'Identity Language Selection',
    f02_name: 'Name',
    f03_father: "Father's Name",
    f04_guardian: 'Guardian',
    f05_date_of_birth: 'Date of Birth',
    f06_nid_number: 'NID Number',
    f07_birth_reg_number: 'Birth Registration Number',
    f08_passport_number: 'Passport Number',
    f09_perm_village_housing: 'Village / Housing No.',
    f10_perm_ward_no: 'Ward No.',
    f11_perm_post_office: 'Post Office',
    f12_perm_thana: 'Thana / Police Station',
    f13_perm_district: 'District',
    f14_perm_division: 'Division',
    f15_perm_country: 'Country',
    f16_pres_village_housing: 'Village / Housing No.',
    f17_pres_post_office: 'Post Office',
    f18_pres_thana: 'Thana / Police Station',
    f19_pres_district: 'District',
    f20_pres_division: 'Division',
    f21_pres_country: 'Country',
    f22_contact_mobile: 'Mobile Number',
    f23_whatsapp_imo: 'WhatsApp / Imo',
    f24_facebook: 'Facebook',
    f25_email: 'E-mail',
    f26_educational_qualification: 'Educational Qualification',
    f27_profession: 'Profession',
    f28_workplace: 'Workplace',
    f29_workplace_thana: 'Workplace Thana',
    f30_workplace_district: 'Workplace District',
    f31_workplace_country: 'Country Name',
    f32_workplace_city: 'City',
    f33_workplace_mobile: 'Mobile Number',
    f34_dawra_hadith: 'Dawra-e-Hadith',
    f35_takhassus: 'Takhassus',
    f36_hifz: 'Hifz',
    f37_takhassus_type: 'Type of Takhassus',
    f38_dawra_hijri_year: 'Dawra-e-Hadith Completion Year (Hijri)',
    f39_dawra_gregorian_year: 'Dawra-e-Hadith Completion Year (Gregorian)',
    f40_takhassus_hijri_year: 'Takhassus Completion Year (Hijri)',
    f41_takhassus_gregorian_year: 'Takhassus Completion Year (Gregorian)',
    f42_hifz_hijri_year: 'Hifz Completion Year (Hijri)',
    f43_hifz_gregorian_year: 'Hifz Completion Year (Gregorian)',
    f44_fee_payment_method: 'Fee Payment Method',
    f45_nid_passport_file: 'NID / Passport',
    f46_photo_file: 'Photo',
    f47_money_receipt_file: 'Money Receipt',
    f48_date: 'Date',
    f49_signature: 'Signature',
  },
};
EOF

cat << 'EOF' > frontend/src/locales/ar.ts
import { TranslationDictionary } from './types';

export const ar: TranslationDictionary = {
  meta: {
    dir: 'rtl',
    langName: 'العربية',
    foundationName: 'فاضلان جامعة فتية فاونديشن',
    shortTagline: 'منصة توثيق البيانات والتواصل وخدمة خريجي الجامعة',
  },
  nav: {
    home: 'الرئيسية',
    about: 'عن المؤسسة',
    purpose: 'الأهداف',
    guidelines: 'التعليمات',
    contact: 'اتصل بنا',
    registerBtn: 'التسجيل الإلكتروني',
    adminLogin: 'لوحة الإدارة',
  },
  home: {
    heroBadge: 'البوابة الرسمية لتسجيل الأعضاء',
    heroTitle: 'فاضلان جامعة فتية فاونديشن',
    heroSubtitle:
      'منصة رقمية آمنة ومتعددة اللغات لحفظ بيانات خريجي الجامعة الإسلامية بفتية، وتعزيز التواصل، وتنظيم المبادرات العلمية والاجتماعية والخيرية.',
    registerNow: 'سجّل الآن إلكترونياً',
    learnMore: 'اقرأ تعليمات التسجيل',
    introTitle: 'التعريف بالمؤسسة',
    introBody:
      'مؤسسة فاضلان جامعة فتية هي منصة جامعة لخريجي الجامعة الإسلامية بفتية من العلماء والمحدثين والمفتين والحفاظ المقيمين داخل البلاد وخارجها.',
    aboutTitle: 'عن المؤسسة',
    aboutBody:
      'تهدف المؤسسة إلى توحيد صفوف خريجي جامعة فتية حول العالم، وإنشاء قاعدة بيانات موثقة ومحدثة، وتفعيل التعاون في المجالات التعليمية والدعوية والاجتماعية.',
    purposeTitle: 'أهداف التسجيل',
    purposePoints: [
      'إنشاء قاعدة بيانات دقيقة وموثقة لجميع الخريجين داخل الوطن وخارجه.',
      'تنظيم قوائم الخريجين في دورة الحديث والتخصص والحفظ حسب السنوات الدراسية.',
      'تعزيز التواصل المهني والتعاون الأخوي بين الأعضاء حسب التخصص ومكان العمل.',
      'تسهيل التنسيق السريع للمشاريع الخيرية والعلمية المستقبلية.',
    ],
    guidelinesTitle: 'تعليمات التسجيل',
    guidelinesSteps: [
      'لا يتطلب التسجيل إنشاء حساب أو تسجيل دخول؛ يمكنك البدء مباشرة بالضغط على زر "التسجيل الإلكتروني".',
      'اختر لغة التعريف المناسبة (البنغالية أو الإنجليزية أو العربية) وأدخل بياناتك الشخصية بدقة.',
      'أدخل العنوان الدائم والعنوان الحالي بشكل منفصل (مع إمكانية النسخ التلقائي إذا تطابقا).',
      'قم برفع نسخة واضحة من الهوية الوطنية أو جواز السفر، والصورة الشخصية، وإيصال الدفع، والتوقيع.',
      'راجع جميع البيانات قبل الإرسال النهائي، واحفظ رقم التسجيل الفريد الظاهر بعد الإرسال.',
    ],
    contactTitle: 'معلومات التواصل',
    contactSubtitle: 'لأي استفسار حول التسجيل أو تحديث البيانات، يرجى التواصل معنا عبر القنوات التالية.',
    officeAddressLabel: 'المقر الرئيسي',
    officeAddress: 'فتية، شيتاغونغ، بنغلاديش',
    phoneLabel: 'رقم المساعدة',
    emailLabel: 'البريد الإلكتروني',
    footerCopyright: '© ٢٠٢٦ فاضلان جامعة فتية فاونديشن. جميع الحقوق محفوظة.',
  },
  formSections: {
    s1: 'القسم الأول: البيانات الشخصية',
    s2: 'القسم الثاني: العنوان الدائم',
    s3: 'القسم الثالث: العنوان الحالي',
    s4: 'القسم الرابع: بيانات التواصل',
    s5: 'القسم الخامس: البيانات التعليمية والمهنية',
    s6: 'القسم السادس: الأقسام العلمية والتخصص',
    s7: 'القسم السابع: سنوات التخرج الدراسية',
    s8: 'القسم الثامن: الرسوم والمرفقات',
    s9: 'القسم التاسع: البيانات الختامية',
    copyPermanentAddress: 'تعبئة العنوان الحالي تلقائياً من العنوان الدائم',
  },
  fields49: {
    f01_identity_language: 'اختيار لغة التعريف',
    f02_name: 'الاسم',
    f03_father: 'اسم الأب',
    f04_guardian: 'ولي الأمر',
    f05_date_of_birth: 'تاريخ الميلاد',
    f06_nid_number: 'رقم الهوية الوطنية',
    f07_birth_reg_number: 'رقم شهادة الميلاد',
    f08_passport_number: 'رقم جواز السفر',
    f09_perm_village_housing: 'القرية / رقم المسكن',
    f10_perm_ward_no: 'رقم الحي / الدائرة',
    f11_perm_post_office: 'مكتب البريد',
    f12_perm_thana: 'مركز الشرطة / المنطقة',
    f13_perm_district: 'المقاطعة / المديرية',
    f14_perm_division: 'الإقليم / المحافظة',
    f15_perm_country: 'الدولة',
    f16_pres_village_housing: 'القرية / رقم المسكن',
    f17_pres_post_office: 'مكتب البريد',
    f18_pres_thana: 'مركز الشرطة / المنطقة',
    f19_pres_district: 'المقاطعة / المديرية',
    f20_pres_division: 'الإقليم / المحافظة',
    f21_pres_country: 'الدولة',
    f22_contact_mobile: 'رقم الجوال',
    f23_whatsapp_imo: 'واتساب / إيمو',
    f24_facebook: 'فيسبوك',
    f25_email: 'البريد الإلكتروني',
    f26_educational_qualification: 'المؤهل العلمي',
    f27_profession: 'المهنة',
    f28_workplace: 'مقر العمل',
    f29_workplace_thana: 'منطقة العمل',
    f30_workplace_district: 'مقاطعة العمل',
    f31_workplace_country: 'اسم الدولة',
    f32_workplace_city: 'المدينة',
    f33_workplace_mobile: 'رقم الجوال',
    f34_dawra_hadith: 'دورة الحديث',
    f35_takhassus: 'التخصص',
    f36_hifz: 'حفظ القرآن الكريم',
    f37_takhassus_type: 'نوع التخصص',
    f38_dawra_hijri_year: 'سنة إتمام دورة الحديث (هجري)',
    f39_dawra_gregorian_year: 'سنة إتمام دورة الحديث (ميلادي)',
    f40_takhassus_hijri_year: 'سنة إتمام التخصص (هجري)',
    f41_takhassus_gregorian_year: 'سنة إتمام التخصص (ميلادي)',
    f42_hifz_hijri_year: 'سنة إتمام الحفظ (هجري)',
    f43_hifz_gregorian_year: 'سنة إتمام الحفظ (ميلادي)',
    f44_fee_payment_method: 'وسيلة دفع الرسوم',
    f45_nid_passport_file: 'الهوية الوطنية / جواز السفر',
    f46_photo_file: 'الصورة الشخصية',
    f47_money_receipt_file: 'إيصال الدفع',
    f48_date: 'التاريخ',
    f49_signature: 'التوقيع',
  },
};
EOF

cat << 'EOF' > frontend/src/context/LanguageContext.tsx
'use client';

import React, { createContext, useContext, useEffect, useState } from 'react';
import { Locale, TranslationDictionary } from '@/locales/types';
import { bn } from '@/locales/bn';
import { en } from '@/locales/en';
import { ar } from '@/locales/ar';

const dictionaries: Record<Locale, TranslationDictionary> = { bn, en, ar };

interface LanguageContextType {
  locale: Locale;
  setLocale: (lang: Locale) => void;
  t: TranslationDictionary;
  dir: 'ltr' | 'rtl';
}

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

export function LanguageProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>('bn');

  useEffect(() => {
    const saved = localStorage.getItem('fjp_locale') as Locale | null;
    if (saved && dictionaries[saved]) {
      setLocaleState(saved);
    }
  }, []);

  useEffect(() => {
    const dict = dictionaries[locale];
    document.documentElement.lang = locale;
    document.documentElement.dir = dict.meta.dir;
    localStorage.setItem('fjp_locale', locale);
  }, [locale]);

  const setLocale = (lang: Locale) => {
    setLocaleState(lang);
  };

  return (
    <LanguageContext.Provider
      value={{
        locale,
        setLocale,
        t: dictionaries[locale],
        dir: dictionaries[locale].meta.dir,
      }}
    >
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage() {
  const context = useContext(LanguageContext);
  if (!context) {
    throw new Error('useLanguage must be used within a LanguageProvider');
  }
  return context;
}
EOF

cat << 'EOF' > frontend/src/app/globals.css
@import "tailwindcss";

:root {
  --brand-green-dark: #0b462b;
  --brand-green-mid: #13633f;
  --brand-gold: #d4af37;
  --brand-gold-light: #f4e6b2;
  --brand-white: #ffffff;
  --brand-surface: #f8faf9;
}

body {
  background-color: var(--brand-white);
  color: #1a2e25;
  overflow-x: hidden;
}

html[dir="rtl"] body {
  font-family: var(--font-arabic), sans-serif;
}

html[lang="bn"] body {
  font-family: var(--font-bengali), sans-serif;
}

html[lang="en"] body {
  font-family: var(--font-english), sans-serif;
}
EOF

cat << 'EOF' > frontend/src/app/layout.tsx
import type { Metadata } from 'next';
import { Noto_Sans_Bengali, Amiri, Plus_Jakarta_Sans } from 'next/font/google';
import './globals.css';
import { LanguageProvider } from '@/context/LanguageContext';

const notoBengali = Noto_Sans_Bengali({
  subsets: ['bengali'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-bengali',
});

const amiriArabic = Amiri({
  subsets: ['arabic'],
  weight: ['400', '700'],
  variable: '--font-arabic',
});

const jakartaSans = Plus_Jakarta_Sans({
  subsets: ['latin'],
  weight: ['400', '500', '600', '700'],
  variable: '--font-english',
});

export const metadata: Metadata = {
  title: 'ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন | Fazelan-e Jamia Foundation',
  description: 'বহুভাষিক অনলাইন নিবন্ধন ও তথ্য ব্যবস্থাপনা ওয়েবসাইট',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="bn"
      dir="ltr"
      className={`${notoBengali.variable} ${amiriArabic.variable} ${jakartaSans.variable}`}
    >
      <body className="min-h-screen flex flex-col bg-white text-[#1a2e25] antialiased">
        <LanguageProvider>{children}</LanguageProvider>
      </body>
    </html>
  );
}
EOF

cat << 'EOF' > frontend/src/components/layout/Header.tsx
'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { useLanguage } from '@/context/LanguageContext';
import { Locale } from '@/locales/types';

export default function Header() {
  const { locale, setLocale, t } = useLanguage();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const languages: { code: Locale; label: string }[] = [
    { code: 'bn', label: 'বাংলা' },
    { code: 'en', label: 'English' },
    { code: 'ar', label: 'العربية' },
  ];

  return (
    <header className="sticky top-0 z-50 bg-[#0b462b] text-white shadow-md border-b-2 border-[#d4af37]">
      <div className="bg-[#07331f] border-b border-[#13633f] py-1.5 px-4">
        <div className="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-2 text-xs">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[#f4e6b2]">
            <span className="font-semibold">ফাজেলানে জামিয়া পটিয়া ফাউন্ডেশন</span>
            <span className="hidden sm:inline opacity-60">|</span>
            <span>Fazelan-e Jamia Foundation</span>
            <span className="hidden sm:inline opacity-60">|</span>
            <span dir="rtl" className="font-bold">فاضلان جامعة فتية فاونديشن</span>
          </div>

          <div className="flex items-center gap-1" role="group" aria-label="Language Switcher">
            {languages.map((lang) => (
              <button
                key={lang.code}
                type="button"
                onClick={() => setLocale(lang.code)}
                className={`px-2.5 py-1 rounded text-xs font-medium transition-colors cursor-pointer ${
                  locale === lang.code
                    ? 'bg-[#d4af37] text-[#07331f] font-bold'
                    : 'bg-[#13633f] text-white hover:bg-[#197c50]'
                }`}
              >
                {lang.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between gap-4">
        <Link href="/" className="flex items-center gap-3 min-w-0">
          <div className="w-11 h-11 rounded-full bg-white border-2 border-[#d4af37] flex items-center justify-center shrink-0 shadow">
            <span className="text-[#0b462b] font-bold text-sm">FJP</span>
          </div>
          <div className="truncate">
            <h1 className="text-base sm:text-lg font-bold text-white truncate">
              {t.meta.foundationName}
            </h1>
            <p className="text-[11px] sm:text-xs text-[#f4e6b2] truncate">
              {t.meta.shortTagline}
            </p>
          </div>
        </Link>

        <nav className="hidden lg:flex items-center gap-6 text-sm font-medium">
          <Link href="/#intro" className="hover:text-[#f4e6b2] transition-colors">
            {t.nav.home}
          </Link>
          <Link href="/#about" className="hover:text-[#f4e6b2] transition-colors">
            {t.nav.about}
          </Link>
          <Link href="/#purpose" className="hover:text-[#f4e6b2] transition-colors">
            {t.nav.purpose}
          </Link>
          <Link href="/#guidelines" className="hover:text-[#f4e6b2] transition-colors">
            {t.nav.guidelines}
          </Link>
          <Link href="/#contact" className="hover:text-[#f4e6b2] transition-colors">
            {t.nav.contact}
          </Link>
          <Link
            href="/register"
            className="bg-[#d4af37] hover:bg-[#e0be4b] text-[#07331f] font-bold px-4 py-2 rounded-lg shadow transition-colors"
          >
            {t.nav.registerBtn}
          </Link>
        </nav>

        <div className="flex lg:hidden items-center gap-2">
          <Link
            href="/register"
            className="bg-[#d4af37] text-[#07331f] font-bold px-3 py-2 rounded-lg text-xs sm:text-sm"
          >
            {t.nav.registerBtn}
          </Link>
          <button
            type="button"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            className="p-2 rounded-lg bg-[#13633f] text-white"
            aria-label="Toggle Menu"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              {mobileMenuOpen ? (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              ) : (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              )}
            </svg>
          </button>
        </div>
      </div>

      {mobileMenuOpen && (
        <nav className="lg:hidden bg-[#07331f] border-t border-[#13633f] px-4 py-3 flex flex-col gap-2 text-sm">
          <Link href="/#intro" onClick={() => setMobileMenuOpen(false)} className="py-2 border-b border-[#13633f]/50">
            {t.nav.home}
          </Link>
          <Link href="/#about" onClick={() => setMobileMenuOpen(false)} className="py-2 border-b border-[#13633f]/50">
            {t.nav.about}
          </Link>
          <Link href="/#purpose" onClick={() => setMobileMenuOpen(false)} className="py-2 border-b border-[#13633f]/50">
            {t.nav.purpose}
          </Link>
          <Link href="/#guidelines" onClick={() => setMobileMenuOpen(false)} className="py-2 border-b border-[#13633f]/50">
            {t.nav.guidelines}
          </Link>
          <Link href="/#contact" onClick={() => setMobileMenuOpen(false)} className="py-2">
            {t.nav.contact}
          </Link>
        </nav>
      )}
    </header>
  );
}
EOF

cat << 'EOF' > frontend/src/app/page.tsx
'use client';

import React from 'react';
import Link from 'next/link';
import Header from '@/components/layout/Header';
import { useLanguage } from '@/context/LanguageContext';

export default function HomePage() {
  const { t } = useLanguage();

  return (
    <div className="min-h-screen flex flex-col bg-[#f8faf9]">
      <Header />

      <main className="flex-1">
        <section
          id="intro"
          className="bg-gradient-to-br from-[#0b462b] via-[#0f5435] to-[#07331f] text-white py-14 sm:py-20 px-4 border-b-4 border-[#d4af37]"
        >
          <div className="max-w-5xl mx-auto text-center">
            <span className="inline-block px-4 py-1.5 rounded-full bg-[#13633f] border border-[#d4af37]/60 text-[#f4e6b2] text-xs sm:text-sm font-medium mb-5">
              {t.home.heroBadge}
            </span>
            <h2 className="text-3xl sm:text-5xl font-bold mb-5 leading-tight">
              {t.home.heroTitle}
            </h2>
            <p className="text-base sm:text-lg text-gray-100 max-w-3xl mx-auto mb-8 leading-relaxed">
              {t.home.heroSubtitle}
            </p>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
              <Link
                href="/register"
                className="w-full sm:w-auto px-8 py-3.5 rounded-xl bg-[#d4af37] hover:bg-[#e0be4b] text-[#07331f] font-bold text-base shadow-lg transition-transform active:scale-95"
              >
                {t.home.registerNow}
              </Link>
              <Link
                href="#guidelines"
                className="w-full sm:w-auto px-8 py-3.5 rounded-xl border border-[#f4e6b2]/60 text-white hover:bg-white/10 font-semibold text-base transition-colors"
              >
                {t.home.learnMore}
              </Link>
            </div>
          </div>
        </section>

        <section id="about" className="py-12 sm:py-16 px-4 max-w-6xl mx-auto">
          <div className="grid md:grid-cols-2 gap-6">
            <div className="bg-white p-6 sm:p-8 rounded-2xl shadow-sm border border-[#d4af37]/30">
              <h3 className="text-xl sm:text-2xl font-bold text-[#0b462b] mb-3 pb-2 border-b-2 border-[#f4e6b2]">
                {t.home.introTitle}
              </h3>
              <p className="text-gray-700 leading-relaxed">{t.home.introBody}</p>
            </div>
            <div className="bg-white p-6 sm:p-8 rounded-2xl shadow-sm border border-[#d4af37]/30">
              <h3 className="text-xl sm:text-2xl font-bold text-[#0b462b] mb-3 pb-2 border-b-2 border-[#f4e6b2]">
                {t.home.aboutTitle}
              </h3>
              <p className="text-gray-700 leading-relaxed">{t.home.aboutBody}</p>
            </div>
          </div>
        </section>

        <section id="purpose" className="py-12 px-4 bg-white border-y border-gray-200">
          <div className="max-w-6xl mx-auto">
            <h3 className="text-2xl sm:text-3xl font-bold text-[#0b462b] text-center mb-8">
              {t.home.purposeTitle}
            </h3>
            <div className="grid sm:grid-cols-2 gap-4">
              {t.home.purposePoints.map((point, idx) => (
                <div
                  key={idx}
                  className="flex items-start gap-3 p-5 rounded-xl bg-[#f8faf9] border border-[#0b462b]/15"
                >
                  <span className="w-8 h-8 rounded-full bg-[#0b462b] text-[#f4e6b2] font-bold flex items-center justify-center shrink-0 text-sm">
                    {idx + 1}
                  </span>
                  <p className="text-gray-800 leading-relaxed">{point}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section id="guidelines" className="py-12 sm:py-16 px-4 max-w-5xl mx-auto">
          <h3 className="text-2xl sm:text-3xl font-bold text-[#0b462b] text-center mb-8">
            {t.home.guidelinesTitle}
          </h3>
          <div className="bg-white rounded-2xl p-6 sm:p-8 shadow-sm border-2 border-[#d4af37]/40 space-y-4">
            {t.home.guidelinesSteps.map((step, idx) => (
              <div key={idx} className="flex items-start gap-3.5">
                <span className="w-7 h-7 rounded-lg bg-[#f4e6b2] text-[#07331f] font-bold flex items-center justify-center shrink-0 text-sm">
                  ✓
                </span>
                <p className="text-gray-700 leading-relaxed">{step}</p>
              </div>
            ))}
            <div className="pt-4 text-center">
              <Link
                href="/register"
                className="inline-block px-8 py-3 rounded-xl bg-[#0b462b] hover:bg-[#13633f] text-white font-bold shadow transition-colors"
              >
                {t.home.registerNow}
              </Link>
            </div>
          </div>
        </section>

        <section id="contact" className="py-12 px-4 bg-[#0b462b]/5 border-t border-[#d4af37]/30">
          <div className="max-w-5xl mx-auto text-center">
            <h3 className="text-2xl sm:text-3xl font-bold text-[#0b462b] mb-2">
              {t.home.contactTitle}
            </h3>
            <p className="text-gray-600 mb-8">{t.home.contactSubtitle}</p>
            <div className="grid sm:grid-cols-3 gap-4 text-start">
              <div className="bg-white p-5 rounded-xl border border-[#d4af37]/30 shadow-sm">
                <p className="text-xs font-semibold text-[#13633f] uppercase mb-1">
                  {t.home.officeAddressLabel}
                </p>
                <p className="font-semibold text-gray-800">{t.home.officeAddress}</p>
              </div>
              <div className="bg-white p-5 rounded-xl border border-[#d4af37]/30 shadow-sm">
                <p className="text-xs font-semibold text-[#13633f] uppercase mb-1">
                  {t.home.phoneLabel}
                </p>
                <p className="font-semibold text-gray-800" dir="ltr">+880 1XXX-XXXXXX</p>
              </div>
              <div className="bg-white p-5 rounded-xl border border-[#d4af37]/30 shadow-sm">
                <p className="text-xs font-semibold text-[#13633f] uppercase mb-1">
                  {t.home.emailLabel}
                </p>
                <p className="font-semibold text-gray-800 break-all" dir="ltr">info@fazelanjamia.org</p>
              </div>
            </div>
          </div>
        </section>
      </main>

      <footer className="bg-[#07331f] text-white border-t-2 border-[#d4af37] py-6 px-4">
        <div className="max-w-7xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3 text-sm">
          <p className="text-[#f4e6b2] text-center sm:text-start">{t.home.footerCopyright}</p>
          <Link href="/admin/login" className="text-xs text-gray-300 hover:text-[#d4af37] underline">
            {t.nav.adminLogin}
          </Link>
        </div>
      </footer>
    </div>
  );
}
EOF

# ১-ক্লিক সার্ভার চালু করার স্ক্রিপ্ট
echo "[6/6] সার্ভার চালানোর স্ক্রিপ্ট তৈরি করা হচ্ছে..."
cat << 'EOF' > start_dev.sh
#!/usr/bin/env bash
sudo service postgresql start
(cd backend && php artisan serve --host=0.0.0.0 --port=8000) &
(cd frontend && npm run dev -- -H 0.0.0.0 -p 3000)
EOF
chmod +x start_dev.sh

echo "=========================================="
echo " ধাপ ১ সম্পন্ন! এখন রান করতে লিখুন: bash start_dev.sh"
echo "=========================================="
