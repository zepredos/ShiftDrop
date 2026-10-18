import os

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

import pytest
from PySide6.QtWidgets import QApplication


@pytest.fixture(scope='session')
def application():
    app = QApplication.instance() or QApplication([])
    yield app


@pytest.fixture
def image_file(tmp_path):
    from PIL import Image, ImageDraw
    path = tmp_path / 'Original.png'
    image = Image.new('RGBA', (120, 80), (255, 140, 30, 255))
    ImageDraw.Draw(image).rectangle((0, 0, 59, 39), fill=(25, 100, 220, 255))
    image.save(path)
    return path
